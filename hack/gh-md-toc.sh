#!/usr/bin/env bash

#
# Add template placeholder to your markdown file
#
# <!--ts-->
# <!--te-->
#
# Call
# ./hack/gh-md-toc.sh --insert --no-backup <your-markdown-file>
#

# Source: https://github.com/ekalinin/github-markdown-toc

gh_toc_version="0.6.2"

gh_user_agent="gh-md-toc v$gh_toc_version"

#
# Download rendered into html README.md by its url.
#
#
gh_toc_load() {
    local gh_url=$1

    if type curl &>/dev/null; then
        curl --user-agent "$gh_user_agent" -s "$gh_url"
    elif type wget &>/dev/null; then
        wget --user-agent="$gh_user_agent" -qO- "$gh_url"
    else
        echo "Please, install 'curl' or 'wget' and try again."
        exit 1
    fi
}

#
# Converts local md file into html by GitHub
#
# ➥ curl -X POST --data '{"text": "Hello world github/linguist#1 **cool**, and #1!"}' https://api.github.com/markdown
# <p>Hello world github/linguist#1 <strong>cool</strong>, and #1!</p>'"
gh_toc_md2html() {
    local gh_file_md=$1
    URL=https://api.github.com/markdown/raw

    if [ -n "$GH_TOC_TOKEN" ]; then
        TOKEN=$GH_TOC_TOKEN
    else
        TOKEN_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/token.txt"
        if [ -f "$TOKEN_FILE" ]; then
            TOKEN=$(cat "$TOKEN_FILE")
        fi
    fi
    if [ -n "${TOKEN}" ]; then
        AUTHORIZATION="--header \"Authorization: token ${TOKEN}\""
    fi

    # echo $URL 1>&2
    OUTPUT="$(curl -s --user-agent "$gh_user_agent" \
        --data-binary @"$gh_file_md" -H "Content-Type:text/plain" \
        "$AUTHORIZATION" \
        $URL)"

    # shellcheck disable=SC2181
    if [ "$?" != "0" ]; then
        echo "XXNetworkErrorXX"
    fi
    if [ "$(echo "${OUTPUT}" | awk '/API rate limit exceeded/')" != "" ]; then
        echo "XXRateLimitXX"
    else
        echo "${OUTPUT}"
    fi
}


#
# Is passed string url
#
gh_is_url() {
    case $1 in
        https* | http*)
            echo "yes";;
        *)
            echo "no";;
    esac
}

#
# TOC generator
#
gh_toc(){
    local gh_src=$1
    local gh_src_copy=$1
    local gh_ttl_docs=$2
    local need_replace=$3
    local no_backup=$4

    if [ "$gh_src" = "" ]; then
        echo "Please, enter URL or local path for a README.md"
        exit 1
    fi


    # Show "TOC" string only if working with one document
    if [ "$gh_ttl_docs" = "1" ]; then

        echo "Table of Contents"
        echo "================="
        echo ""
        gh_src_copy=""

    fi

    if [ "$(gh_is_url "$gh_src")" == "yes" ]; then
        gh_toc_load "$gh_src" | gh_toc_grab "$gh_src_copy"
        if [ "${PIPESTATUS[0]}" != "0" ]; then
            echo "Could not load remote document."
            echo "Please check your url or network connectivity"
            exit 1
        fi
        if [ "$need_replace" = "yes" ]; then
            echo
            echo "!! '$gh_src' is not a local file"
            echo "!! Can't insert the TOC into it."
            echo
        fi
    else
        local rawhtml
        rawhtml=$(gh_toc_md2html "$gh_src")
        if [ "$rawhtml" == "XXNetworkErrorXX" ]; then
             echo "Parsing local markdown file requires access to github API"
             echo "Please make sure curl is installed and check your network connectivity"
             exit 1
        fi
        if [ "$rawhtml" == "XXRateLimitXX" ]; then
             echo "Parsing local markdown file requires access to github API"
             echo "Error: You exceeded the hourly limit. See: https://developer.github.com/v3/#rate-limiting"
             TOKEN_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/token.txt"
             echo "or place GitHub auth token here: ${TOKEN_FILE}"
             exit 1
        fi
        local toc
        toc=$(echo "$rawhtml" | gh_toc_grab "$gh_src_copy")
        echo "$toc"
        if [ "$need_replace" = "yes" ]; then
            if grep -Fxq "<!--ts-->" "$gh_src" && grep -Fxq "<!--te-->" "$gh_src"; then
                echo "Found markers"
            else
                echo "You don't have <!--ts--> or <!--te--> in your file...exiting"
                exit 1
            fi
            local ts
            ts="<\!--ts-->"
            local te
            te="<\!--te-->"
            local dt
            dt=$(date +'%F_%H%M%S')
            local ext
            ext=".orig.${dt}"
            local toc_path
            toc_path="${gh_src}.toc.${dt}"
            local toc_footer
            toc_footer="<!-- Added by: $(whoami), at: $(date) -->"
            # http://fahdshariff.blogspot.ru/2012/12/sed-mutli-line-replacement-between-two.html
            # clear old TOC
            sed -i"${ext}" "/${ts}/,/${te}/{//!d;}" "$gh_src"
            # create toc file
            echo "${toc}" > "${toc_path}"
            echo -e "\n${toc_footer}\n" >> "$toc_path"
            # insert toc file
            if [[ "$(uname)" == "Darwin" ]]; then
                sed -i "" "/${ts}/r ${toc_path}" "$gh_src"
            else
                sed -i "/${ts}/r ${toc_path}" "$gh_src"
            fi
            echo
            if [ "$no_backup" = "yes" ]; then
                rm "${toc_path}" "${gh_src}${ext}"
            fi
            echo "!! TOC was added into: '$gh_src'"
            if [ -z "$no_backup" ]; then
                echo "!! Origin version of the file: '${gh_src}${ext}'"
                echo "!! TOC added into a separate file: '${toc_path}'"
	    fi
            echo
        fi
    fi
}

#
# Grabber of the TOC from rendered html
#
# $1 — a source url of document.
# It's need if TOC is generated for multiple documents.
#
gh_toc_grab() {
	# if closed <h[1-6]> is on the new line, then move it on the prev line
	# for example:
	# 	was: The command <code>foo1</code>
	# 		 </h1>
	# 	became: The command <code>foo1</code></h1>
    sed -e ':a' -e 'N' -e '$!ba' -e 's/\n<\/h/<\/h/g' |
    # find strings that corresponds to template
    grep -E -o '<a.*id="user-content-[^"]*".*</h[1-6]' |
    # remove code tags
    sed 's/<code>//g' | sed 's/<\/code>//g' |
    # now all rows are like:
    #   <a id="user-content-..." href="..."><span ...></span></a> ... </h1
    # format result line
    #   * $0 — whole string
    #   * last element of each row: "</hN" where N in (1,2,3,...)
    echo -e "$(awk -v "gh_url=$1" '{
    level = substr($0, length($0), 1)
    text = substr($0, match($0, /a>.*<\/h/)+2, RLENGTH-5)
    href = substr($0, match($0, "href=\"[^\"]+?\"")+6, RLENGTH-7)
    print sprintf("%*s", level*3, " ") "* [" text "](" gh_url  href ")" }' |
        sed 'y/+/ /; s/%/\\x/g')"
}

#
# Returns filename only from full path or url
#
gh_toc_get_filename() {
    echo "${1##*/}"
}

#
# Options handlers
#
gh_toc_app() {
    local need_replace
    need_replace="no"

    if [ "$1" = '--help' ] || [ $# -eq 0 ] ; then
        local app_name
        app_name=$(basename "$0")
        echo "GitHub TOC generator ($app_name): $gh_toc_version"
        echo ""
        echo "Usage:"
        echo "  $app_name [--insert] src [src]  Create TOC for a README file (url or local path)"
        echo "  $app_name [--no-backup] src [src]  Create TOC without backup, requires <!--ts--> / <!--te--> placeholders"
        echo "  $app_name -                     Create TOC for markdown from STDIN"
        echo "  $app_name --help                Show help"
        echo "  $app_name --version             Show version"
        return
    fi

    if [ "$1" = '--version' ]; then
        echo "$gh_toc_version"
        echo
        echo "os:     $(lsb_release -d | cut -f 2)"
        echo "kernel: $(cat /proc/version)"
        echo "shell:  $($SHELL --version)"
        echo
        for tool in curl wget grep awk sed; do
            printf "%-5s: " $tool
            # shellcheck disable=SC2005
            echo "$($tool --version | head -n 1)"
        done
        return
    fi

    # shellcheck disable=SC2166
    if [ "$1" = "-" ]; then
        if [ -z "$TMPDIR" ]; then
            TMPDIR="/tmp"        
        elif [ -n "$TMPDIR" -a ! -d "$TMPDIR" ]; then
            mkdir -p "$TMPDIR"
        fi
        local gh_tmp_md
        gh_tmp_md=$(mktemp $TMPDIR/tmp.XXXXXX)
        while read -r input; do
            echo "$input" >> "$gh_tmp_md"
        done
        gh_toc_md2html "$gh_tmp_md" | gh_toc_grab ""
        return
    fi

    if [ "$1" = '--insert' ]; then
        need_replace="yes"
        shift
    fi

    if [ "$1" = '--no-backup' ]; then
        need_replace="yes"
        no_backup="yes"
        shift
    fi
    for md in "$@"
    do
        echo ""
        gh_toc "$md" "$#" "$need_replace" "$no_backup"
    done

    echo ""
    echo "Created by [gh-md-toc](https://github.com/ekalinin/github-markdown-toc)"
}

#
# Entry point
#
gh_toc_app "$@"
#!/bin/bash
# Software: command_shad - Steam Collection downloader for lgsm/Starbound
# Variables to add to lgsm config file: 
#USER
# - steamuser=your steam login name
#	-	steampass=your steam login password
# - steamcollections=a comma seperated list of the collections you'd like to download on steam
# - steamapikey=your steam web API key (not necessary at this time)
#OPTIONAL
# - steam_collectionapicall=full URL to the steam GetCollectionDetails api
# - steam_publishedapicall=full URL to the steam GetPublishedFileDetails api
# - curlcmd=the path and options you'd like to use for curl (default provided)
#FILES (command will use lgsm defined temp directory by degfault)
# - steamscriptfile=full file path to the temporary script file to be created for steamcmd
# - jsonawkfile=full file path to the temporary JSON.awk file you'd like to use (default provided)


# Version: 1.0a
# Author: jusjinxed on Discord / github
# License: This software is licensed under the MIT license.
# Project home: https://github.com/JustJinxed/command_shad
# Credits: shadow_absorber of the Frakin Universe team on Discord for the very idea and encouragement
#  fair enough ;)

main () {
#Check for JSON.awk in tmpdir defined by server. If it doesn't exist, create it.
: ${jsonawkfile:="${tmpdir}/JSON.awk"}
[ ! -f "${jsonawkfile}" ] && echo "Creating ${jsonawkfile}..." && JSONAWK

#Check for the required basics
[[ -z ${steamuser} || -z ${steampass} ]] && echo "You must set the steamuser AND steampass variables in your configuration file(s)" && exit 15
[[ -z ${steamcollections} ]] && echo "Must set steamcollections to a comma delimited list of the collections you'd like to download" && exit 16

#The user need not set these, as most API web calls, don't actually require the key
#But just incase Steam changes things, we have a slot for that.
: ${steamapikey:='0'}
: ${steam_publishedapicall:="https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"}
: ${steam_collectionapicall:="https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/"}
: ${curlcmd:="curl -s --data"}
: ${steamscriptfile:="${tmpdir}/steam_script.ss"}
IFS=',' read -r -a steamcollections <<< $steamcollections #inplace convert steamcollections variable, to an array

### Get the titles for the requested steamcollections
X="\"key=${steamapikey}&itemcount=${#steamcollections[@]}"
for i in "${!steamcollections[@]}"; do
	X+="&publishedfileids[${i}]=${steamcollections[$i]}"
done
X+="\" ${steam_publishedapicall}" 
readarray -t json_file < <(curl -s --data ${X} | awk -f ${jsonawkfile} "-")

echo -n "Collections being marked for download: "
X=()
for hash in "${json_file[@]}"; do 
	read response param <<< ${hash}
	if [[ "${response}" =~ \"response\",\"publishedfiledetails\"\,([^\,]*)\,\"title\" ]]; then
		X+=("${param//'"'/}")
	fi
done

for hash in ${!X[@]}; do
	echo -n ${X[hash]}
	[[ ${hash} != $((${#X[@]}-1)) ]] && echo -n ", "
	[[ ${hash} == $((${#X[@]}-2)) ]] && echo -n "and "
done
echo
### End steamcollections Gathering


### Build an API query to get the publishedfileids from the steamcollections
X="\"key=${steamapikey}&collectioncount=${#steamcollections[@]}"
for i in ${!steamcollections[@]}; do
	X+="&publishedfileids[${i}]=${steamcollections[$i]}"
done
X+="\" ${steam_collectionapicall}"
#Execute the curl and pass the output to awk using JSON template
readarray -t json_dump < <(curl -s --data ${X} | awk -f ${jsonawkfile} "-")


exec 3> "${steamscriptfile}" # Open a filedescript for a temporary steamscript
#echo "login ${steamuser} ${steampass}" >&3 #horribly insecure. For testing purposes only!
echo "force_install_dir ${serverfiles}" >&3


### iterate through the json_dump we received from curl/awk
#
#
for hash in "${json_dump[@]}"; do #must be quoted for lf in json output
	read response param <<< ${hash} #split the hash into a response and param
	stripped_response=${response:1:${#response}-2} #stripped bracket version of response [not needed]
	var1=${response//'"'/} #strip quotes from response [it's a numeric field, so replace is fine]
	param=${param//'"'/} #strip any quotes from the resulting param [for looks and just in case a param has a glob]
	IFS=',' read -r -a response_array <<< ${stripped_response} # split response into an array [might not be needed]

	# Let's assign some variables and act accordingly
	#	We shall assume every publishedfileid response in the JSON will end in a filetype
	#	Upon receiving the filetype, we'll assume the proper data for the collection and
	#	publishedfileid has already been via prior lines in the JSON/if blocks.

	if [[ "${response}" =~ \"response\"\,\"collectiondetails\"\,([^\,]*)\,\"publishedfileid\" ]]; then
		current_collection=$((${BASH_REMATCH[1]}+1))
		echo Collection: ${current_collection} SteamID: ${param} .. found.
	fi

	[[ "${response}" =~ \"response\"\,\"collectiondetails\"\,([^\,]*)\,\"children\"\,([^\,]*)\,\"publishedfileid\" ]] && \
		collection=$((${BASH_REMATCH[1]}+1)) && \
		child=$((${BASH_REMATCH[2]}+1)) && \
		fileid=${param}

	if [[ "${response}" =~ \"response\"\,\"collectiondetails\"\,([^\,]*)\,\"children\"\,([^\,]*)\,\"filetype\" ]] && [[ ${param} == 0 ]]; then
		published_array+=($fileid)
		echo "workshop_download_item 211820 ${fileid}" >&3
	fi
done

### Let's get a alpha description of all these mods?
# Not necessary, but while we're here, we might as well.
# Since this is throw away for now,  We'll reuse these
# variables and code -/- why not?
# Don't forget to IF block this out, JJ

echo && echo "List of all mods being downlaoded from workshop: "
echo "(You may see some duplicates if one collection has the same mod as another)"
for i in {1..75}; do echo -n -; done; echo

X="\"key=${steamapikey}&itemcount=${#published_array[@]}"
for i in "${!published_array[@]}"; do
	X+="&publishedfileids[${i}]=${published_array[$i]}"
done
X+="\" ${steam_publishedapicall}" 

readarray -t json_file < <(curl -s --data ${X} | awk -f ${jsonawkfile} "-")
for hash in "${json_file[@]}"; do 
	read response param <<< ${hash}
	if [[ "${response}" =~ \"response\"\,\"publishedfiledetails\"\,([^\,]*)\,\"title\" ]]; then
			param=${param:1:${#param}-2}; #strip the outside quotes from mod title
			echo "${param}"
	fi
done

echo "quit" >&3
exec 3>&-

${steamcmddir}/steamcmd.sh +login ${steamuser} ${steampass} +runscript ${steamscriptfile}

}

JSONAWK () {
cat << '_EOF' > "${tmpdir}/JSON.awk"
#!/usr/bin/awk -f
# Software: JSON.awk - a practical JSON parser written in awk
# Version: 1.11a
# Author: step- on github.com
# License: This software is licensed under the MIT or the Apache 2 license.
# Project home: https://github.com/step-/JSON.awk.git
# Credits: This software includes major portions of JSON.sh, a pipeable JSON
#   parser written in Bash, retrieved on 20130313
#   https://github.com/dominictarr/JSON.sh
#

# See README.md for extended usage instructions.
# Usage:
#   printf "%s\n" Filepath [Filepath...] "" | awk [-v Option="value"] [-v Option="value"...] -f JSON.awk
# Options: (default value in braces)
#   BRIEF=0  don't print non-leaf nodes {1}
#   STREAM=0  don't print to stdout, and store jpaths in JPATHS[] {1}

BEGIN { #{{{
	if (BRIEF == "") BRIEF=1 # parse() omits printing non-leaf nodes
	if (STREAM == "") STREAM=1; # parse() omits stdout and stores jpaths in JPATHS[]
	# for each input file:
	#   TOKENS[], NTOKENS, ITOKENS - tokens after tokenize()
	#   JPATHS[], NJPATHS - parsed data (when STREAM=0)
	# at script exit:
	#   FAILS[] - maps names of invalid files to logged error lines
	delete FAILS

	if (1 == ARGC) {
		# file pathnames from stdin
		# usage: echo -e "file1\nfile2\n" | awk -f JSON.awk
		# usage: { echo; cat file1; } | awk -f JSON.awk
		while (getline ARGV[++ARGC] < "/dev/stdin") {
			if (ARGV[ARGC] == "")
				break
		}
	} # else usage: awk -f JSON.awk file1 [file2...]

	# set file slurping mode
	srand(); RS="n/o/m/a/t/c/h" rand()
}
#}}}

{ # main loop: process each file in turn {{{
	reset() # See important application note in reset()

	tokenize($0) # while(get_token()) {print TOKEN}
	if (0 == parse()) {
		apply(JPATHS, NJPATHS)
	}
}
#}}}

END { # process invalid files {{{
	for(name in FAILS) {
		print "invalid: " name
		print FAILS[name]
	}
}
#}}}

function apply (ary, size,   i) { # stub {{{
	for (i=1; i<size; i++)
		print ary[i]
}
#}}}

function get_token() { #{{{
# usage: {tokenize($0); while(get_token()) {print TOKEN}}

	# return getline TOKEN # for external tokenizer

	TOKEN = TOKENS[++ITOKENS] # for internal tokenize()
	return ITOKENS < NTOKENS
}
#}}}

function parse_array(a1,   idx,ary,ret) { #{{{
	idx=0
	ary=""
	get_token()
#scream("parse_array(" a1 ") TOKEN=" TOKEN)
	if (TOKEN != "]") {
		while (1) {
			if (ret = parse_value(a1, idx)) {
				return ret
			}
			idx=idx+1
			ary=ary VALUE
			get_token()
			if (TOKEN == "]") {
				break
			} else if (TOKEN == ",") {
				ary = ary ","
			} else {
				report(", or ]", TOKEN ? TOKEN : "EOF")
				return 2
			}
			get_token()
		}
	}
	if (1 != BRIEF) {
		VALUE=sprintf("[%s]", ary)
	} else {
		VALUE=""
	}
	return 0
}
#}}}

function parse_object(a1,   key,obj) { #{{{
	obj=""
	get_token()
#scream("parse_object(" a1 ") TOKEN=" TOKEN)
	if (TOKEN != "}") {
		while (1) {
			if (TOKEN ~ /^".*"$/) {
				key=TOKEN
			} else {
				report("string", TOKEN ? TOKEN : "EOF")
				return 3
			}
			get_token()
			if (TOKEN != ":") {
				report(":", TOKEN ? TOKEN : "EOF")
				return 4
			}
			get_token()
			if (parse_value(a1, key)) {
				return 5
			}
			obj=obj key ":" VALUE
			get_token()
			if (TOKEN == "}") {
				break
			} else if (TOKEN == ",") {
				obj=obj ","
			} else {
				report(", or }", TOKEN ? TOKEN : "EOF")
				return 6
			}
			get_token()
		}
	}
	if (1 != BRIEF) {
		VALUE=sprintf("{%s}", obj)
	} else {
		VALUE=""
	}
	return 0
}
#}}}

function parse_value(a1, a2,   jpath,ret,x) { #{{{
	jpath=(a1!="" ? a1 "," : "") a2 # "${1:+$1,}$2"
#scream("parse_value(" a1 "," a2 ") TOKEN=" TOKEN ", jpath=" jpath)
	if (TOKEN == "{") {
		if (parse_object(jpath)) {
			return 7
		}
	} else if (TOKEN == "[") {
		if (ret = parse_array(jpath)) {
			return ret
		}
	} else if (TOKEN == "") { #test case 20150410 #4
		report("value", "EOF")
		return 9
	} else if (TOKEN ~ /^([^0-9])$/) {
		# At this point, the only valid single-character tokens are digits.
		report("value", TOKEN)
		return 9
	} else {
		VALUE=TOKEN
	}
	if (! (1 == BRIEF && ("" == jpath || "" == VALUE))) {
		x=sprintf("[%s]\t%s", jpath, VALUE)
		if(0 == STREAM) {
			JPATHS[++NJPATHS] = x
		} else {
			print x
		}
	}
	return 0
}
#}}}

function parse(   ret) { #{{{
	get_token()
	if (ret = parse_value()) {
		return ret
	}
	if (get_token()) {
		report("EOF", TOKEN)
		return 11
	}
	return 0
}
#}}}

function report(expected, got,   i,from,to,context) { #{{{
	from = ITOKENS - 10; if (from < 1) from = 1
	to = ITOKENS + 10; if (to > NTOKENS) to = NTOKENS
	for (i = from; i < ITOKENS; i++)
		context = context sprintf("%s ", TOKENS[i])
	context = context "<<" got ">> "
	for (i = ITOKENS + 1; i <= to; i++)
		context = context sprintf("%s ", TOKENS[i])
	scream("expected <" expected "> but got <" got "> at input token " ITOKENS "\n" context)
}
#}}}

function reset() { #{{{
# Application Note:
# If you need to build JPATHS[] incrementally from multiple input files:
# 1) Comment out below:        delete JPATHS; NJPATHS=0
#    otherwise each new input file would reset JPATHS[].
# 2) Move the call to apply() from the main loop to the END statement.
# 3) In the main loop consider adding code that deletes partial JPATHS[]
#    elements that would result from parsing invalid JSON files.
# Compatibility Note:
# 1) Very old gawk versions: replace 'delete JPATHS' with 'split("", JPATHS)'.

	TOKEN=""; delete TOKENS; NTOKENS=ITOKENS=0
	delete JPATHS; NJPATHS=0
	VALUE=""
}
#}}}

function scream(msg) { #{{{
	FAILS[FILENAME] = FAILS[FILENAME] (FAILS[FILENAME]!="" ? "\n" : "") msg
	msg = FILENAME ": " msg
	print msg >"/dev/stderr"
}
#}}}

function tokenize(a1,   pq,pb,ESCAPE,CHAR,STRING,NUMBER,KEYWORD,SPACE) { #{{{
# usage A: {for(i=1; i<=tokenize($0); i++) print TOKENS[i]}
# see also get_token()

	# POSIX character classes (gawk) - contact me for non-[:class:] notation
	# Replaced regex constant for string constant, see https://github.com/step-/JSON.awk/issues/1
#	ESCAPE="(\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})"
#	CHAR="[^[:cntrl:]\\\"]"
#	STRING="\"" CHAR "*(" ESCAPE CHAR "*)*\""
#	NUMBER="-?(0|[1-9][0-9]*)([.][0-9]*)?([eE][+-]?[0-9]*)?"
#	KEYWORD="null|false|true"
	SPACE="[[:space:]]+"

#        gsub(STRING "|" NUMBER "|" KEYWORD "|" SPACE "|.", "\n&", a1)
	gsub(/\"[^[:cntrl:]\"\\]*((\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})[^[:cntrl:]\"\\]*)*\"|-?(0|[1-9][0-9]*)([.][0-9]*)?([eE][+-]?[0-9]*)?|null|false|true|[[:space:]]+|./, "\n&", a1)
        gsub("\n" SPACE, "\n", a1)
	sub(/^\n/, "", a1)
	ITOKENS=0 # get_token() helper
	return NTOKENS = split(a1, TOKENS, /\n/)
}
#}}}

# vim:fdm=marker:
_EOF
}

main


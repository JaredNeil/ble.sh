#!/usr/bin/env bash

umask 022
shopt -s nullglob

function mkd {
  [[ -d $1 ]] || mkdir -p "$1"
}

function download {
  local url=$1 dst=$2
  if [[ ! -s $dst ]]; then
    [[ $dst == ?*/* ]] && mkd "${dst%/*}"
    if type wget &>/dev/null; then
      wget "$url" -O "$dst.part" && mv "$dst.part" "$dst"
    else
      echo "make_command: 'wget' not found." >&2
      exit 2
    fi
  fi
}

function ble/array#push {
  while (($#>=2)); do
    builtin eval "$1[\${#$1[@]}]=\$2"
    set -- "$1" "${@:3}"
  done
}

function sub:help {
  printf '%s\n' \
         'usage: make_command.sh SUBCOMMAND args...' \
         '' 'SUBCOMMAND' ''
  local sub
  for sub in $(declare -F | sed -n 's|^declare -[fx]* sub:\([^/]*\)$|\1|p'); do
    if declare -f sub:"$sub"/help &>/dev/null; then
      sub:"$sub"/help
    else
      printf '  %s\n' "$sub"
    fi
  done
  printf '\n'
}

#------------------------------------------------------------------------------

function sub:install {
  # read options
  local flag_error= flag_release=
  local opt_strip_comment=
  while [[ $1 == -* ]]; do
    local arg=$1; shift
    case $arg in
    (--release) flag_release=1 ;;
    (--strip-comment=*)
      opt_strip_comment=${arg#*=} ;;
    (*) echo "install: unknown option $arg" >&2
        flag_error=1 ;;
    esac
  done
  [[ $flag_error ]] && return 1

  local src=$1
  local dst=$2
  mkd "${dst%/*}"
  if [[ $src == *.sh ]]; then
    local nl=$'\n' q=\'

    # header comment
    local script='1i\
# Copyright 2015 Koichi Murase <myoga.murase@gmail.com>. All rights reserved.\
# This script is a part of blesh (https://github.com/akinomyoga/ble.sh)\
# provided under the BSD-3-Clause license.  Do not edit this file because this\
# is not the original source code: Various pre-processing has been applied.\
# Also, the code comments and blank lines are stripped off in the installation\
# process.  Please find the corresponding source file(s) in the repository\
# "akinomyoga/ble.sh".'
    if [[ $src == out/ble.sh ]]; then
      script=$script'\
#\
# Source: /ble.pp'
      local file
      for file in $(git ls-files src); do
        [[ $file == *.sh ]] || continue
        script=$script"\\
# Source: /$file"
      done
    else
      script=$script'\
#\
# Source: /'"${src#out/}"
    fi

    # strip comments
    if [[ $opt_strip_comment != no ]]; then
      script=$script'
/<<[[:space:]]*EOF/,/^[[:space:]]*EOF/{p;d;}
/^[[:space:]]*#/d
/^[[:space:]]*$/d'
    else
      script=$script'\
#------------------------------------------------------------------------------'
    fi

    [[ $flag_release ]] &&
      script=$script$nl's/^\([[:space:]]*_ble_base_repository=\)'$q'.*'$q'\([[:space:]]*\)$/\1'${q}release:$dist_git_branch$q'/'
    sed "$script" "$src" >| "$dst.part" && mv "$dst.part" "$dst"
  else
    cp "$src" "$dst"
  fi
}
function sub:install/help {
  printf '  install src dst\n'
}

function sub:uninstall {
  rm -rf "$@"

  local file children
  for file; do
    while
      file=${file%/*}
      [[ -d $file ]] || break
      children=("$file"/* "$file"/.*)
      ((${#children[@]} == 0))
    do
      rmdir "$file"
    done
  done
}

function sub:dist {
  local dist_git_branch=$(git rev-parse --abbrev-ref HEAD)
  local tmpdir=ble-$FULLVER
  local src
  for src in "$@"; do
    local dst=$tmpdir${src#out}
    sub:install --release "$src" "$dst"
  done
  [[ -d dist ]] || mkdir -p dist
  tar caf "dist/$tmpdir.$(date +'%Y%m%d').tar.xz" "$tmpdir" && rm -r "$tmpdir"
}

function sub:ignoreeof-messages {
  (
    cd ~/local/build/bash-4.3/po
    sed -nr '/msgid "Use \\"%s\\" to leave the shell\.\\n"/{n;s/^[[:space:]]*msgstr "(.*)"[^"]*$/\1/p;}' *.po | while builtin read -r line || [[ $line ]]; do
      [[ $line ]] || continue
      echo $(printf "$line" exit) # $() は末端の改行を削除するため
    done
  ) >| lib/core-edit.ignoreeof-messages.new
}

#------------------------------------------------------------------------------
# sub:check
# sub:check-all

function sub:check {
  local bash=${1-bash}
  "$bash" out/ble.sh --test
}
function sub:check-all {
  local -x _ble_make_command_check_count=0
  local bash rex_version='^bash-([0-9]+)\.([0-9]+)$'
  for bash in $(compgen -c -- bash- | grep -E '^bash-(dev|[0-9]+\.[0-9]+)$' | sort -Vr); do
    [[ $bash =~ $rex_version && ${BASH_REMATCH[1]} -ge 3 ]] || continue
    "$bash" out/ble.sh --test || return 1
    ((_ble_make_command_check_count++))
  done
}

#------------------------------------------------------------------------------
# sub:scan

_make_rex_escseq='(\[[ -?]*[@-~])*'

function sub:scan/grc-source {
  local -a options=(--color --exclude=./{test,memo,ext,wiki,contrib,[TD]????.*} --exclude=\*.{md,awk} --exclude=./{GNUmakefile,make_command.sh})
  grc "${options[@]}" "$@"
}
function sub:scan/list-command {
  local -a options=(--color --exclude=./{test,memo,ext,wiki,contrib,[TD]????.*} --exclude=\*.{md,awk})

  # read arguments
  local flag_exclude_this= flag_error=
  local command=
  while (($#)); do
    local arg=$1; shift
    case $arg in
    (--exclude-this)
      flag_exclude_this=1 ;;
    (--exclude=*)
      ble/array#push options "$arg" ;;
    (--)
      [[ $1 ]] && command=$1
      break ;;
    (-*)
      echo "check: unknown option '$arg'" >&2
      flag_error=1 ;;
    (*)
      command=$arg ;;
    esac
  done
  if [[ ! $command ]]; then
    echo "check: command name is not specified." >&2
    flag_error=1
  fi
  [[ $flag_error ]] && return 1

  [[ $flag_exclude_this ]] && ble/array#push options --exclude=./make_command.sh
  grc "${options[@]}" "(^|[^-./\${}=#])\b$command"'\b([[:space:]|&;<>()`"'\'']|$)'
}

function sub:scan/builtin {
  echo "--- $FUNCNAME $1 ---"
  local command=$1 esc=$_make_rex_escseq
  sub:scan/list-command --exclude-this --exclude={generate-release-note.sh,lib/test-*.sh,make,ext} "$command" "${@:2}" |
    grep -Ev "$rex_grep_head([[:space:]]*|[[:alnum:][:space:]]*[[:space:]])#|(\b|$esc)(builtin|function)$esc([[:space:]]$esc)+$command(\b|$esc)" |
    grep -Ev "$command(\b|$esc)=" |
    grep -Ev "ble\.sh $esc\($esc$command$esc\)$esc" |
    sed -E 'h;s/'"$_make_rex_escseq"'//g
        \Z^\./lib/test-[^:]+\.sh:[0-9]+:.*ble/test Zd
      s/^[^:]*:[0-9]+:[[:space:]]*//
        \Z(\.awk|push|load|==|#(push|pop)) \b'"$command"'\bZd
      g'
}

function sub:scan/check-todo-mark {
  echo "--- $FUNCNAME ---"
  grc --color --exclude=./make_command.sh '@@@'
}
function sub:scan/a.txt {
  echo "--- $FUNCNAME ---"
  grc --color --exclude={test,ext,./lib/test-\*.sh,./make_command.sh,\*.md} --exclude=check-mem.sh '[/[:space:]<>"'\''][a-z]\.txt|/dev/(pts/|pty)[0-9]*|/dev/tty' |
    sed -E 'h;s/'"$_make_rex_escseq"'//g
      \Z^\./memo/Zd
      \Zgithub302-perlre-server\.bashZd
      \Z^\./contrib/integration/fzf-git.bash:[0-9]+:Zd
    s/^[^:]*:[0-9]+:[[:space:]]*//
      \Z^[[:space:]]*#Zd
      \ZDEBUG_LEAKVARZd
      \Z\[\[ -t 4 && -t 5 ]]Zd
      \Z^ble/fd#alloc .*Zd
      \Zbuiltin read -et 0.000001 dummy </dev/ttyZd
      g'
}

function sub:scan/bash300bug {
  echo "--- $FUNCNAME ---"
  # bash-3.0 では local arr=(1 2 3) とすると
  # local arr='(1 2 3)' と解釈されてしまう。
  grc '(local|declare|typeset) [_a-zA-Z]+=\(' --exclude=./{test,ext} --exclude=./make_command.sh --exclude=ChangeLog.md --color |
    grep -v '#D0184'

  # bash-3.0 では local -a arr=("$hello") とすると
  # クォートしているにも拘らず $hello の中身が単語分割されてしまう。
  grc '(local|declare|typeset) -a [[:alnum:]_]+=\([^)]*[\"'\''`]' --exclude=./{test,ext} --exclude=./make_command.sh --color |
    grep -v '#D0525'

  # bash-3.0 では "${scalar[@]/xxxx}" は全て空になる
  grc '\$\{[_a-zA-Z0-9]+\[[*@]\]/' --exclude=./{text,ext} --exclude=./make_command.sh --exclude=\*.md --color |
    grep -v '#D1570'

  # bash-3.0 では "..${var-$'hello'}.." は (var が存在しない時) "..'hello'..." になる。
  grc '".*\$\{[^{}]*\$'\''([^\\'\'']|\\.)*'\''\}.*"' --exclude={./make_command.sh,memo,\*.md} --color |
    grep -v '#D1774'

}

function sub:scan/bash301bug-array-element-length {
  echo "--- $FUNCNAME ---"
  # bash-3.1 で ${#arr[index]} を用いると、
  # 日本語の文字数が変になる。
  grc '\$\{#[[:alnum:]]+\[[^@*]' --exclude={test,ChangeLog.md} --color |
    grep -Ev '^([^#]*[[:space:]])?#' |
    grep -v '#D0182'
}

function sub:scan/bash400bug {
  echo "--- $FUNCNAME ---"

  # bash-3.0..4.0 で $'' 内に \' を入れていると '' の入れ子状態が反転して履歴展
  # 開が '' の内部で起こってしまう。
  grc '\$'\''([^\'\'']|\\[^'\''])*\\'\''([^\'\'']|\\.|'\''([^\'\'']|\\*)'\'')*![^=[:space:]]' --exclude={test,ChangeLog.md} --color |
    grep -v '9f0644470'
}

function sub:scan/bash401-histexpand-bgpid {
  echo "--- $FUNCNAME ---"
  grc '"\$!"' --exclude={test,ChangeLog.md} --color |
    grep -Ev '#D2028'
}

function sub:scan/bash404-no-argument-return {
  echo "--- $FUNCNAME ---"
  grc --color 'return[[:space:]]*($|[;|&<>])' --exclude={test,wiki,ChangeLog.md,make,docs,make_command.sh} |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//

      \Z@returnZd
      \Z\) return;Zd
      \Zreturn;[[:space:]]*$Zd
      \Zif \(REQ == "[A-Z]+"\)Zd
      \Z\(return\|ret\)Zd
      \Z_ble_trap_done=return$Zd
      \Z\bwe return\bZd

      g'
}

function sub:scan/bash501-arith-base {
  echo "--- $FUNCNAME ---"
  # bash-5.1 で $((10#)) の取り扱いが変わった。
  grc '\b10#\$' --exclude={test,ChangeLog.md}
}

function sub:scan/bash502-patsub_replacement {
  echo "--- $FUNCNAME ---"
  # bash-5.2 patsub_replacement で ${var/pat/string} の string 中の & が特別な
  # 意味を持つ様になったので、特に意識する場合を除いては quote が必要になった。
  grc --color '\$\{[[:alnum:]_]+(\[[^][]*\])?//?([^{}]|\{[^{}]*\})+/[^{}"'\'']*([&$]|\\)' --exclude=./test |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Z//?\$q/\$Q\}Zd
      \Z//?\$q/\$qq\}Zd
      \Z//?\$qq/\$q\}Zd
      \Z//?\$__ble_q/\$__ble_Q\}Zd
      \Z//?\$_ble_local_q/\$_ble_local_Q\}Zd
      \Z/\$\(\([^()]+\)\)\}Zd
      \Z/\$'\''([^\\]|\\.)+'\''\}Zd

      \Z\$\{[_a-zA-Z0-9]+//(ARR|DICT|PREFIX|NAME|LAYER)/\$([_a-zA-Z0-9]+|\{[_a-zA-Z0-9#:-]+\})\}Zd
      \Z\$\{[_a-zA-Z0-9]+//'\''%[dlcxy]'\''/\$[_a-zA-Z0-9]+\}Zd # src/canvas.sh

      \Z#D1738Zd
      \Z\$\{_ble_edit_str//\$'\''\\n'\''/\$'\''\\n'\''"\$comment_begin"\}Zd # edit.sh
      g'

  grc --color '"[^"]*\$\{[[:alnum:]_]+(\[[^][]*\])?//?([^{}]|\{[^{}]*\})+/[^{}"'\'']*"[^"]*([&$]|\\)' --exclude=./test |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Z#D1751Zd
      g'
}

function sub:scan/gawk402bug-regex-check {
  echo "--- $FUNCNAME ---"
  grc --color '\[\^?\][^]]*\[:[^]]*:\].[^]]*\]' --exclude={test,ext,\*.md} | grep -Ev '#D1709 safe'
}

function sub:scan/assign {
  echo "--- $FUNCNAME ---"
  local command="$1"
  grc --color --exclude=./test --exclude=./memo '\$\([^()]' |
    grep -Ev "$rex_grep_head#|[[:space:]]#"
}

function sub:scan/memo-numbering {
  echo "--- $FUNCNAME ---"

  grep -ao '\[#D....\]' note.txt memo/done.txt | awk '
    function report_error(message) {
      printf("memo-numbering: \x1b[1;31m%s\x1b[m\n", message) > "/dev/stderr";
    }
    !/\[#D[0-9]{4}\]/ {
      report_error("invalid  number \"" $0 "\".");
      next;
    }
    {
      num = $0;
      gsub(/^\[#D0+|\]$/, "", num);
      if (prev != "" && num != prev - 1) {
        if (prev < num) {
          report_error("reverse ordering " num " has come after " prev ".");
        } else if (prev == num) {
          report_error("duplicate number " num ".");
        } else {
          for (i = prev - 1; i > num; i--) {
            report_error("memo-numbering: missing number " i ".");
          }
        }
      }
      prev = num;
    }
    END {
      if (prev != 1) {
        for (i = prev - 1; i >= 1; i--)
          report_error("memo-numbering: missing number " i ".");
      }
    }
  '
  cat note.txt memo/done.txt | sed -n '0,/^[[:space:]]\{1,\}Done/d;/  \* .*\[#D....\]$/d;/^  \* /p'
}

# 誤って ((${#arr[@]})) を ((${arr[@]})) などと書いてしまうミス。
function sub:scan/array-count-in-arithmetic-expression {
  echo "--- $FUNCNAME ---"
  grc --exclude=./make_command.sh '\(\([^[:space:]]*\$\{[[:alnum:]_]+\[[@*]\]\}'
}

# unset 変数名 としていると誤って関数が消えることがある。
function sub:scan/unset-variable {
  echo "--- $FUNCNAME ---"
  sub:scan/list-command unset --exclude-this |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Zunset[[:space:]]-[vf]Zd
      \Z^[[:space:]]*#Zd
      \Zunset _ble_init_(version|arg|exit|command)\bZd
      \Zbuiltins1=\(.* unset .*\)Zd
      \Zfunction unsetZd
      \Zreadonly -f unsetZd
      \Z'\''\(unset\)'\''Zd
      \Z"\$__ble_proc" "\$__ble_name" unsetZd
      \Zulimit umask unalias unset waitZd
      \ZThe variable will be unset initiallyZd
      g'
}
function sub:scan/eval-literal {
  echo "--- $FUNCNAME ---"
  sub:scan/grc-source 'builtin eval "\$' |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Zeval "(\$[[:alnum:]_]+)+(\[[^]["'\''\$`]+\])?\+?=Zd
      g'
}

function sub:scan/WA-localvar_inherit {
  echo "--- $FUNCNAME ---"
  grc 'local [^;&|()]*"\$\{[_a-zA-Z0-9]+\[@*\]\}"' |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Ztest_command='\''ble/bin/stty -echo -nl -icrnl -icanon "\$\{_ble_term_stty_flags_enter\[@]}" size'\''Zd
      g'
}

function sub:scan/mistake-_ble_bash {
  echo "--- $FUNCNAME ---"
  grc '\(\(.*\b_ble_base\b.*\)\)'
}

function sub:scan/command-layout {
  echo "--- $FUNCNAME ---"
  grc '/(enter-command-layout|\.insert-newline|\.newline)([[:space:]]|$)' --exclude=./{text,ext} --exclude=./make_command.sh --exclude=\*.md --color |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Z^[[:space:]]*#Zd
      \Z^[[:space:]]*function [^[:space:]]* \{$Zd
      \Z[: ]keep-infoZd
      \Z#D1800Zd
      g'
}

function sub:scan/word-splitting-number {
  echo "--- $FUNCNAME ---"
  # #D1835 一般には IFS に整数が含まれるている場合もあるので ${#...} や
  # $((...)) や >&$fd であってもちゃんと quote する必要がある。
  grc '[<>]&\$|([[:space:]]|=\()\$(\(\(|\{#|\?)' --exclude={docs,mwg_pp.awk,memo} |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Z^[^#]*(^|[[:space:]])#Zd
      \Z^([^"]|"[^\#]*")*"[^"]*([& (]\$)Zd
      \Z^[^][]*\[\[[^][]*([& (]\$)Zd
      \Z\(\([_a-zA-Z0-9]+=\(\$Zd
      \Z\$\{#[_a-zA-Z0-9]+\}[<>?&]Zd
      \Z \$\{\#[_a-zA-Z0-9]+\[@\]\} -gt 0 \]\]Zd
      \Zcase \$\? inZd
      \Zcase \$\(\(.*\)\) inZd
      g'
}

function sub:scan/check-readonly-unsafe {
  echo "--- $FUNCNAME ---"
  local rex_varname='\b(_[_a-zA-Z0-9]+|[_A-Z][_A-Z0-9]+)\b'
  grc -Wg,-n -Wg,--color=always -o "$rex_varname"'\+?=\b|(/assign|/assign-array|#split) '"$rex_varname"'| -v '"$rex_varname"' ' --exclude={memo,wiki,test,make,\*.md,make_command.sh,GNUmakefile} |
    sed -E 'h;s/'"$_make_rex_escseq"'//g

      # Exceptions in each file
      /^\.\/ble.pp:[0-9]*:BLEOPT=$/d
      /^\.\/lib\/core-complete.sh:[0-9]+:KEY=$/d
      /^\.\/lib\/core-syntax.sh:[0-9]+:VAR=$/d
      /^\.\/lib\/init-(cmap|term).sh:[0-9]+:TERM=$/d
      /^\.\/src\/edit.sh:[0-9]+:_dirty=$/d
      /^\.\/src\/history.sh:[0-9]+:_history_index=$/d
      /^\.\/src\/util.sh:[0-9]+:(ARRI|OPEN|TERM)=$/d
      /^\.\/lib\/core-cmdspec.sh:[0-9]+:OLD=$/d

      # (extract only variable names)
      s/^[^:]*:[0-9]+:[[:space:]]*//;
      s/^-v (.*) $/\1/;s/\+?=$//;s/^.+ //;

      # other frameworks & integrations
      /^__bp_blesh_invoking_through_blesh$/d
      /^BP_PROMPT_COMMAND_.*$/d

      # common variables
      /^__?ble[_a-zA-Z0-9]*$/d
      /^[A-Z]$/d
      /^BLE_[_A-Z0-9]*$/d
      /^ADVICE_[_A-Z0-9]*$/d
      /^COMP_[_A-Z0-9]*$/d
      /^COMPREPLY$/d
      /^READLINE_[_A-Z0-9]*$/d
      /^LC_[_A-Z0-9]*$/d
      /^LANG$/d

      # other uppercase variables that ble.sh is allowed to use.
      /^(FUNCNEST|IFS|IGNOREEOF|POSIXLY_CORRECT|TMOUT)$/d
      /^(PWD|OLDPWD|CDPATH)$/d
      /^(BASHPID|GLOBIGNORE|MAPFILE|REPLY)$/d
      /^INPUTRC$/d
      /^(LINES|COLUMNS)$/d
      /^HIST(CONTROL|IGNORE|SIZE|TIMEFORMAT)$/d
      /^(PROMPT_COMMAND|PS1)$/d
      /^(BASH_COMMAND|BASH_REMATCH|HISTCMD|LINENO|PIPESTATUS|TIMEFORMAT)$/d
      /^(BASH_XTRACEFD|PS4)$/d
      /^(CC|LESS|MANOPT|MANPAGER|PAGER|PATH|MANPATH)$/d
      /^(BUFF|KEYS|KEYMAP|WIDGET|LASTWIDGET|DRAW_BUFF)$/d
      /^(D(MIN|MAX|MAX0)|(HIGHLIGHT|PREV)_(BUFF|UMAX|UMIN)|LEVEL|LAYER_(UMAX|UMIN))$/d
      /^(HISTINDEX_NEXT|FILE|LINE|INDEX|INDEX_FILE)$/d
      /^(ARG|FLAG|REG)$/d
      /^(COMP[12SV]|ACTION|CAND|DATA|INSERT|PREFIX_LEN)$/d
      /^(PRETTY_NAME|NAME|VERSION)$/d

      # variables in awk/comments/etc
      /^AWKTYPE$/d
      /^FOO$/d
      g'
}

function sub:scan {
  if ! type grc >/dev/null; then
    echo 'blesh check: grc not found. grc can be found in github.com:akinomyoga/mshex.git/' >&2
    exit
  fi

  local esc=$_make_rex_escseq
  local rex_grep_head="^$esc[[:graph:]]+$esc:$esc[[:digit:]]*$esc:$esc"

  # builtin return break continue : eval echo unset は unset しているので大丈夫のはず

  #sub:scan/builtin 'history'
  sub:scan/builtin 'echo' --exclude=./lib/keymap.vi_test.sh --exclude=./ble.pp |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Z\bstty[[:space:]]+echoZd
      \Zecho \$PPIDZd
      \Zble/keymap:vi_test/check Zd
      \Zmandb-help=%'\''help echo'\''Zd
      \Zalias aaa4='\''echo'\''Zd
      g'
  #sub:scan/builtin '(compopt|type|printf)'
  sub:scan/builtin 'bind' |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Zinvalid bind typeZd
      \Zline = "bind"Zd
      \Z'\''  bindZd
      \Z\(bind\)    ble-bindZd
      \Z^alias bind cd command compgenZd
      \Zoutputs of the "bind" builtinZd
      \Zif ble/string#match "\$_ble_edit_str" '\''bindZd
      g'
  sub:scan/builtin 'read' |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \ZDo not read Zd
      \Zfailed to read Zd
      \Zpushd read readonly set shoptZd
      g'
  sub:scan/builtin 'exit' |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Zble.pp.*return 1 2>/dev/null || exit 1Zd
      \Z^[-[:space:][:alnum:]_./:=$#*]+('\''[^'\'']*|"[^"()`]*|([[:space:]]|^)#.*)\bexit\bZd
      \Z\(exit\) ;;Zd
      \Zprint NR; exit;Zd;g'
  sub:scan/builtin 'eval' |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Z\('\''eval'\''\)Zd
      \Zbuiltins1=\(.* eval .*\)Zd
      \Z\^eval --Zd
      \Zt = "eval -- \$"Zd
      \Ztext = "eval -- \$'\''Zd
      \Zcmd '\''eval -- %q'\''Zd
      \Z\$\(eval \$\(call .*\)\)Zd
      \Z^[[:space:]]*local rex_[_a-zA-Z0-9]+='\''[^'\'']*'\''[[:space:]]*$Zd
      \ZLINENO=\$_ble_edit_LINENO evalZd
      \Z^ble/cmdspec/opts Zd
      g'
  sub:scan/builtin 'unset' |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Zunset _ble_init_(version|arg|exit|command)\bZd
      \Zreadonly -f unsetZd
      \Zunset -f builtinZd
      \Z'\''\(unset\)'\''Zd
      \Z"\$__ble_proc" "\$__ble_name" unsetZd
      \Zumask unalias unset wait$Zd
      \ZThe variable will be unset initiallyZd
      g'
  sub:scan/builtin 'unalias' |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Zbuiltins1=\(.* unalias .*\)Zd
      \Zumask unalias unset wait$Zd
      g'

  #sub:scan/assign
  sub:scan/builtin 'trap' |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Z_ble_trap_handler="trap -- '\''\$\{_ble_trap_handler//\$q/\$Q}'\'' \$nZd
      \Zline = "bind"Zd
      \Ztrap_command=["'\'']trap -- Zd
      \Z_ble_builtin_trap_handlers_reload\[sig\]="trap -- Zd
      \Zlocal trap$Zd
      \Z"trap -- '\''"Zd
      \Z\('\'' trap '\''\*Zd
      \Z\(trap \| ble/builtin/trap\) .*;;Zd
      \Zble/function#trace trap Zd
      \Z# EXIT trapZd
      \Zread readonly set shopt trapZd
      \Zble/util/print "custom trap"Zd
      g'

  sub:scan/builtin 'readonly' |
    sed -E 'h;s/'"$_make_rex_escseq"'//g;s/^[^:]*:[0-9]+:[[:space:]]*//
      \Z^[[:space:]]*#Zd
      \ZWA readonlyZd
      \Z\('\''declare'\''(\|'\''[a-z]+'\'')+\)Zd
      \Z readonly was blocked\.Zd
      \Z\[\[ \$\{FUNCNAME\[i]} == \*readonly ]]Zd
      \Zread readonly set shopt trapZd
      g'

  sub:scan/a.txt
  sub:scan/check-todo-mark
  sub:scan/bash300bug
  sub:scan/bash301bug-array-element-length
  sub:scan/bash400bug
  sub:scan/bash401-histexpand-bgpid
  sub:scan/bash404-no-argument-return
  sub:scan/bash501-arith-base
  sub:scan/bash502-patsub_replacement
  sub:scan/gawk402bug-regex-check
  sub:scan/array-count-in-arithmetic-expression
  sub:scan/unset-variable
  sub:scan/eval-literal
  sub:scan/WA-localvar_inherit
  sub:scan/mistake-_ble_bash
  sub:scan/command-layout
  sub:scan/word-splitting-number
  sub:scan/check-readonly-unsafe

  sub:scan/memo-numbering
}

function sub:show-contrib/canonicalize {
  sed 's/, /\n/g;s/ and /\n/g' | sed 's/[[:space:]]/_/g' | LANG=C sort
}
function sub:show-contrib/count {
  LANG=C sort | uniq -c | LANG=C sort -rnk1 |
    awk 'function xflush() {if(c!=""){printf("%4d %s\n",c,n);}} {if($1!=c){xflush();c=$1;n=$2}else{n=n", "$2;}}END{xflush()}' |
    ifold -w 131 -s --indent=' +[0-9] +'
}
function sub:show-contrib {
  local cache_contrib_github=out/contrib-github.txt
  if [[ ! ( $cache_contrib_github -nt .git/refs/remotes/origin/master ) ]]; then
    {
      wget 'https://api.github.com/repos/akinomyoga/ble.sh/issues?state=all&per_page=100&pulls=true' -O -
      wget 'https://api.github.com/repos/akinomyoga/ble.sh/issues?state=all&per_page=100&pulls=true&page=2' -O -
      wget 'https://api.github.com/repos/akinomyoga/blesh-contrib/issues?state=all&per_page=100&pulls=true' -O -
    } |
      sed -n 's/^[[:space:]]*"login": "\(.*\)",$/\1/p' |
      sub:show-contrib/canonicalize > "$cache_contrib_github"
  fi

  echo "Contributions (from GitHub Issues/PRs)"
  < "$cache_contrib_github" sub:show-contrib/count

  echo "Contributions (from memo.txt)"
  sed -En 's/^  \* .*\([^()]+ by ([^()]+)\).*/\1/p' memo/done.txt note.txt | sub:show-contrib/canonicalize | sub:show-contrib/count

  echo "Contributions (from ChangeLog.md)"
  sed -n 's/.*([^()]* by \([^()]*\)).*/\1/p' docs/ChangeLog.md | sub:show-contrib/canonicalize | sub:show-contrib/count

  echo "Σ: Issues/PRs + max(memo.txt,ChangeLog)"

  LANG=C join -j 2 -e 0 \
      <(sed -En 's/^  \* .*\([^()]+ by ([^()]+)\).*/\1/p' memo/done.txt note.txt | sub:show-contrib/canonicalize | uniq -c | LANG=C sort -k2) \
      <(sed -n 's/.*([^()]* by \([^()]*\)).*/\1/p' docs/ChangeLog.md | sub:show-contrib/canonicalize | uniq -c | LANG=C sort -k2) |
    LANG=C join -e 0 -1 1 - -2 2 <(uniq -c "$cache_contrib_github" | LANG=C sort -k2) |
    awk 'function max(x,y){return x<y?y:x;}{printf("%4d %s\n",max($2,$3)+$4,$1)}' |
    sort -rnk1 |
    awk 'function xflush() {if(c!=""){printf("%4d %s\n",c,n);}} {if($1!=c){xflush();c=$1;n=$2}else{n=n", "$2;}}END{xflush()}' |
    ifold -w 131 -s --indent=' +[0-9] +'
  echo
}

#------------------------------------------------------------------------------
# sub:release-note
#
# 使い方
# ./make_command.sh release-note v0.3.2..v0.3.3

function sub:release-note/help {
  printf '  release-note v0.3.2..v0.3.3 [--changelog CHANGELOG]\n'
}

function sub:release-note/read-arguments {
  flags=
  fname_changelog=memo/ChangeLog.md
  while (($#)); do
    local arg=$1; shift 1
    case $arg in
    (--changelog)
      if (($#)); then
        fname_changelog=$1; shift
      else
        flags=E$flags
        echo "release-note: missing option argument for '$arg'." >&2
      fi ;;
    esac
  done
}

function sub:release-note/.find-commit-pairs {
  {
    echo __MODE_HEAD__
    git log --format=format:'%h%s' --date-order --abbrev-commit "$1"; echo
    echo __MODE_MASTER__
    git log --format=format:'%h%s' --date-order --abbrev-commit master; echo
  } | awk -F '' '
    /^__MODE_HEAD__$/ {
      mode = "head";
      nlist = 0;
      next;
    }
    /^__MODE_MASTER__$/ { mode = "master"; next; }

    function reduce_title(str) {
      str = $2;
      #if (match(str, /^.*\[(originally: )?(.+: .+)\]$/, m)) str = m[2];
      gsub(/["`]/, "", str);
      #print str >"/dev/stderr";
      return str;
    }

    mode == "head" {
      i = nlist++;
      titles[i] = $2;
      commit_head[i] = $1;
      title2index[reduce_title($2)] = i;
    }
    mode == "master" && (i = title2index[reduce_title($2)]) != "" && commit_master[i] == "" {
      commit_master[i] = $1;
    }

    END {
      for (i = 0; i < nlist; i++) {
        print commit_head[i] ":" commit_master[i] ":" titles[i];
      }
    }
  '
}

function sub:release-note {
  local flags fname_changelog
  sub:release-note/read-arguments "$@"

  ## @arr commits
  ##   この配列は after:before の形式の要素を持つ。
  ##   但し after は前の version から release までに加えられた変更の commit である。
  ##   そして before は after に対応する master における commit である。
  local -a commits
  IFS=$'\n' eval 'commits=($(sub:release-note/.find-commit-pairs "$@"))'

  local commit_pair
  for commit_pair in "${commits[@]}"; do
    local hash=${commit_pair%%:*}
    commit_pair=${commit_pair:${#hash}+1}
    local hash_base=${commit_pair%%:*}
    local title=${commit_pair#*:}

    local rex_hash_base=$hash_base
    if ((${#hash_base} == 7)); then
      rex_hash_base=$hash_base[0-9a-f]?
    elif ((${#hash_base} == 8)); then
      rex_hash_base=$hash_base?
    fi

    local result=
    [[ $hash_base ]] && result=$(awk '
        sub(/^##+ +/, "") { heading = "[" $0 "] "; next; }
        sub(/\y'"$rex_hash_base"'\y/, "'"$hash (master: $hash_base)"'") {print heading $0;}
      ' "$fname_changelog")
    if [[ $result ]]; then
      echo "$result"
    elif [[ $title ]]; then
      echo "- $title $hash (master: ${hash_base:-N/A}) ■NOT-FOUND■"
    else
      echo "■not found $hash"
    fi
  done | tac
}

# 以下の様な形式のファイルをセクション毎に分けて出力します。
#
# [Fixes] - foo bar
# [New features] - foo bar
# [Fixes] - foo bar
# [Fixes] - foo bar
# ...
function sub:release-note-sort {
  local file=$1
  awk '
    match($0, /\[[^][]+\]/) {
      key = substr($0, 1, RLENGTH);
      gsub(/^\[|]$/, "", key);

      line = substr($0, RLENGTH + 1);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line);
      if (line == "") next;
      if (line !~ /^- /) line = "- " line;

      if (sect[key] == "")
        keys[nkey++] = key;
      sect[key] = sect[key] line "\n"
      next;
    }
    {print}

    END {
      for (i=0;i<nkey;i++) {
        key = keys[i];
        print "## " key;
        print sect[key];
      }
    }
  ' "$file"
}

#------------------------------------------------------------------------------

function sub:list-functions/help {
  printf '  list-functions [-p] files...\n'
}
function sub:list-functions {
  local -a files; files=()
  local opt_literal=
  local i=0 N=$# args; args=("$@")
  while ((i<N)); do
    local arg=${args[i++]}
    if [[ ! $opt_literal && $arg == -* ]]; then
      if [[ $arg == -- ]]; then
        opt_literal=1
      elif [[ $arg == --* ]]; then
        printf 'list-functions: unknown option "%s"\n' "$arg" >&2
        opt_error=1
      elif [[ $arg == -* ]]; then
        local j
        for ((j=1;j<${#arg};j++)); do
          local o=${arg:j:1}
          case $o in
          (p) opt_public=1 ;;
          (*) printf 'list-functions: unknown option "-%c"\n' "$o" >&2
              opt_error=1 ;;
          esac
        done
      fi
    else
      files+=("$arg")
    fi
  done

  if ((${#files[@]}==0)); then
    files=($(find out -name \*.sh -o -name \*.bash))
  fi

  if [[ $opt_public ]]; then
    local rex_function_name='[^[:space:]()/]*'
  else
    local rex_function_name='[^[:space:]()]*'
  fi
  sed -n 's/^[[:space:]]*function \('"$rex_function_name"'\)[[:space:]].*/\1/p' "${files[@]}" | sort -u
}

function sub:first-defined {
  local name dir
  for name; do
    for dir in ../ble-0.{1..3} ../ble.sh; do
      (cd "$dir"; grc "$name" &>/dev/null) || continue
      echo "$name $dir"
      return 0
    done
  done
  echo "$name not found"
  return 1
}
function sub:first-defined/help {
  printf '  first-defined ERE...\n'
}

#------------------------------------------------------------------------------

function sub:scan-words {
  # sed -E "s/'[^']*'//g;s/(^| )[[:space:]]*#.*/ /g" $(findsrc --exclude={wiki,test,\*.md}) |
  #   grep -hoE '\$\{?[_a-zA-Z][_a-zA-Z0-9]*\b|\b[_a-zA-Z][-:._/a-zA-Z0-9]*\b' |
  #   sed -E 's/^\$\{?//g;s.^ble/widget/..;\./.!d;/:/d' |
  #   sort | uniq -c | sort -n
  sed -E "s/(^| )[[:space:]]*#.*/ /g" $(findsrc --exclude={memo,wiki,test,\*.md}) |
    grep -hoE '\b[_a-zA-Z][_a-zA-Z0-9]{3,}\b' |
    sed -E 's/^bleopt_//' |
    sort | uniq -c | sort -n | less
}
function sub:scan-varnames {
  sed -E "s/(^| )[[:space:]]*#.*/ /g" $(findsrc --exclude={wiki,test,\*.md}) |
    grep -hoE '\$\{?[_a-zA-Z][_a-zA-Z0-9]*\b|\b[_a-zA-Z][_a-zA-Z0-9]*=' |
    sed -E 's/^\$\{?(.*)/\1$/g;s/[$=]//' |
    sort | uniq -c | sort -n | less
}

function sub:check-dependency/identify-funcdef {
  local funcname=$1
  grep -En "\bfunction $funcname +\{" ble.pp src/*.sh | awk -F : -v funcname="$funcname" '
    {
      if ($1 == "ble.pp") {
        if (funcname ~ /^ble\/util\/assign$|^ble\/bin\/grep$/) next;
        if (funcname == "ble/util/print" && $2 < 30) next;
      } else if ($1 == "src/benchmark.sh") {
        if (funcname ~ /^ble\/util\/(unlocal|print|print-lines)$/) next;
      }
      print $1 ":" $2;
      exit
    }
  '
}

function sub:check-dependency {
  local file=$1
  grep -Eo '\bble(hook|opt|-[[:alnum:]]+)?/[^();&|[:space:]'\''"]+' "$file" | sort -u |
    grep -Fvx "$(grep -Eo '\bfunction [^();&|[:space:]'\''"]+ +\{' "$file" | sed -E 's/^function | +\{$//g' | sort -u)" |
    while read -r funcname; do
      location=$(sub:check-dependency/identify-funcdef "$funcname")
      echo "${location:-unknown:0}:$funcname"
    done | sort -t : -Vk 1,2 | less -FSXR
}

#------------------------------------------------------------------------------
# sub:check-readline-bindable

function sub:check-readline-bindable {
  join -v1 <(
    for bash in bash $(compgen -c -- bash-); do
      [[ $bash == bash-[12]* ]] && continue
      "$bash" -c 'bind -l' 2>/dev/null
    done | sort -u
  ) <(sort lib/core-decode.emacs-rlfunc.txt)
}

#------------------------------------------------------------------------------

if (($#==0)); then
  sub:help
elif declare -f sub:"$1" &>/dev/null; then
  sub:"$@"
else
  echo "unknown subcommand '$1'" >&2
  builtin exit 1
fi

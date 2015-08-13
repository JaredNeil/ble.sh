#!/bin/bash
#%(

_ble_util_array_prototype=()
function _ble_util_array_prototype.reserve {
  local n="$1"
  for ((i=${#_ble_util_array_prototype[@]};i<n;i++)); do
    _ble_util_array_prototype[i]=
  done
}

.ble-shopt-extglob-push() { shopt -s extglob;}
.ble-shopt-extglob-pop()  { shopt -u extglob;}

source ble-color.sh

_ble_stackdump_title=stackdump
_ble_term_NL=$'\n'
function ble-stackdump {
  # echo "${BASH_SOURCE[1]} (${FUNCNAME[1]}): assertion failure $*" >&2
  local i nl=$'\n'
  local message="$_ble_term_sgr0$_ble_stackdump_title: $*$nl"
  for ((i=1;i<${#FUNCNAME[*]};i++)); do
    message="$message  @ ${BASH_SOURCE[i]}:${BASH_LINENO[i]} (${FUNCNAME[i]})$nl"
  done
  echo -n "$message" >&2
}
function ble-assert {
  local expr="$1"
  local _ble_stackdump_title='assertion failure'
  if ! eval -- "$expr"; then
    shift
    ble-stackdump "$expr$_ble_term_NL$*"
  fi
}

#%)
#%m main (

## @var _ble_syntax_text
##   解析対象の文字列を保持します
## @var _ble_syntax_stat[i]
##   文字 #i を解釈しようとする直前の状態を記録する。
##   各要素は "ctx wlen wtype nlen" の形式をしている。
##   ctx は現在の文脈。
##   wbegin は現在のシェル単語の継続している長さ。
##   nlen は現在の入れ子状態が継続している長さ。
## @var _ble_syntax_nest[inest]
##   入れ子の情報
##   各要素は "ctx wbegin wtype inest type" の形式をしている。
##   ctx wbegin inest wtype は入れ子を抜けた時の状態を表す。
##   type は入れ子の種類を表す文字列。
## @var _ble_syntax_word[i-1]
##   境界 #i で終わる単語についての情報を保持する。
##   各要素は "wtype wlen" の形式をしている。
## @var _ble_syntax_attr[i]
##   文脈・属性の情報
_ble_syntax_text=
_ble_syntax_stat=()
_ble_syntax_nest=()
_ble_syntax_word=()
_ble_syntax_attr=()

## @var[in,out] word
function ble-syntax/print-status/tree-prepend {
  local -i j="$1"
  local t="$2"
  tree[j]="$t${tree[j]}"
  ((max_tree_width<${#tree[j]}&&(max_tree_width=${#tree[j]})))
}

function ble-syntax/print-status {
  local _result='A?'$'\n'

  local -a tree char line
  tree=()
  char=()
  line=()

  local i iN max_tree_width=0
  for ((i=0,iN=${#_ble_syntax_text};i<iN;i++)); do
    local attr="  ${_ble_syntax_attr[i]:-|}"
    if ((_ble_syntax_attr_umin<=i&&i<_ble_syntax_attr_uend)); then
      attr="${attr:${#attr}-2:2}*"
    else
      attr="${attr:${#attr}-2:2} "
    fi

    local index="000$i"
    index="${index:${#index}-3:3}"

    local word=(${_ble_syntax_word[i]})
    local tword=
    if [[ $word ]]; then
      local l="$((${#word[@]}/4))"
      while ((--l>=0)); do
        local axis=$((i+1))
        local b="$((axis-word[4*l+1]))" e="$axis"
        local _prev="${word[4*l+3]}" _child="${word[4*l+2]}"
        if ((_prev>=0)); then
          _prev="@$((axis-_prev-1))>"
        else
          _prev=
        fi
        if ((_child>=0)); then
          _child=">@$((axis-_child-1))"
        else
          _child=
        fi

        tword=" word=${word[4*l]}:$_prev$b-$e$_child$tword"
        for ((;b<i;b++)); do
          ble-syntax/print-status/tree-prepend b '|'
        done
        ble-syntax/print-status/tree-prepend i '+'
      done
    fi

    local nest=(${_ble_syntax_nest[i]})
    if [[ $nest ]]; then
      local nword='-'
      local nnest='-'
      ((nest[3]>=0)) && nnest="'${nest[4]}':$((i-nest[3]))-"
      ((nest[1]>=0)) && nword="${nest[2]}:$((i-nest[1]))-"
      nest=" nest=(${nest[0]} w=$nword n=$nnest)"
    fi

    local stat=(${_ble_syntax_stat[i]})
    if [[ $stat ]]; then
      local sword=-
      local snest=-
      ((stat[3]>=0)) && snest="@$((i-stat[3]))"
      ((stat[1]>=0)) && sword="${stat[2]}:$((i-stat[1]))-"
      stat=" stat=(${stat[0]} w=$sword n=$snest)"
    fi

    char[i]="$attr $index '${_ble_syntax_text:i:1}'"
    line[i]="$tword$nest$stat"
  done

  _ble_util_string_prototype.reserve max_tree_width
  for ((i=0;i<iN;i++)); do
    local t="${tree[i]}${_ble_util_string_prototype::max_tree_width}"
    _result="$_result${char[i]} ${t::max_tree_width}${line[i]}"$'\n'
  done

  if [[ $1 == -v && $2 ]]; then
    eval "$2=\"\$_result\""
  else
    echo "$_result"
  fi
}

# 文脈値達
CTX_UNSPECIFIED=0
CTX_ARGX=3   # (コマンド) 次に引数が来る
CTX_ARGX0=18 # (コマンド)   文法的には次に引数が来そうだがもう引数が来てはならない文脈。例えば ]] や )) の後。
CTX_CMDX=1   # (コマンド) 次にコマンドが来る。
CTX_CMDXV=13 # (コマンド)   var=val の直後。次にコマンドが来るかも知れないし、来ないかもしれない。
CTX_CMDXF=16 # (コマンド)   for の直後。直後が (( だったら CTX_CMDI に、他の時は CTX_CMDI に。
CTX_CMDX1=17 # (コマンド)   次にコマンドが少なくとも一つ来なければならない。例えば ( や && や while の直後。
CTX_CMDI=2   # (コマンド) context,attr: in a command
CTX_ARGI=4   # (コマンド) context,attr: in an argument
CTX_VRHS=11  # (コマンド) context,attr: var=rhs
CTX_QUOT=5   # context,attr: in double quotations
CTX_EXPR=8   # context,attr: in expression
ATTR_ERR=6   # attr: error
ATTR_VAR=7   # attr: variable
ATTR_QDEL=9  # attr: delimiters for quotation
ATTR_DEF=10  # attr: default (currently not used)
ATTR_DEL=12  # attr: delimiters
ATTR_HISTX=21 # 履歴展開 (!!$ など)
ATTR_FUNCDEF=22 # 関数名 ( hoge() や function fuga など)
CTX_PARAM=14 # (パラメータ展開) context,attr: inside of parameter expansion
CTX_PWORD=15 # (パラメータ展開) context,attr: inside of parameter expansion
CTX_RDRF=19 # (リダイレクト) リダイレクト対象のファイル。
CTX_RDRD=20 # (リダイレクト) リダイレクト対象のファイルディスクリプタ。
CTX_VALX=23 # (値リスト) 次に値が来る
CTX_VALI=24 # (値リスト) 値の中
ATTR_COMMENT=25 # コメント

_BLE_SYNTAX_CSPACE=$' \t\n'
_BLE_SYNTAX_CSPECIAL=()
_BLE_SYNTAX_CSPECIAL[CTX_ARGI]="$_BLE_SYNTAX_CSPACE;|&()<>\$\"\`\\'!^"
_BLE_SYNTAX_CSPECIAL[CTX_QUOT]="\$\"\`\\!"   # 文字列 "～" で特別な意味を持つのは $ ` \ " のみ。+履歴展開の ! も。
_BLE_SYNTAX_CSPECIAL[CTX_EXPR]="][}()\$\"\`\\'!" # ()[] は入れ子を数える為。} は ${var:ofs:len} の為。
_BLE_SYNTAX_CSPECIAL[CTX_PWORD]="}\$\"\`\\!" # パラメータ展開 ${～}

# 入れ子構造の管理

## 関数 ble-syntax/parse/nest-push newctx type
##  @param[in]     newctx 新しい ctx を指定します。
##  @param[in,opt] type   文法要素の種類を指定します。
##  @var  [in]     i      現在の位置を指定します。
##  @var  [in,out] ctx    復帰時の ctx を指定します。新しい ctx (newctx) を返します。
##  @var  [in,out] wbegin 復帰時の wbegin を指定します。新しい wbegin (-1) を返します。
##  @var  [in,out] wtype  復帰時の wtype を指定します。新しい wtype (-1) を返します。
##  @var  [in,out] inest  復帰時の inest を指定します。新しい inest (i) を返します。
function ble-syntax/parse/nest-push {
  local wlen=$((wbegin<0?wbegin:i-wbegin))
  local nlen=$((inest<0?inest:i-inest))
  _ble_syntax_nest[i]="$ctx $wlen $wtype $nlen ${2:-none}"
  ((ctx=$1,inest=i,wbegin=-1,wtype=-1))
  #echo "push inest=$inest @${FUNCNAME[*]:1}"
}
function ble-syntax/parse/nest-pop {
  ((inest<0)) && return 1

  local -a parent
  parent=(${_ble_syntax_nest[inest]})
  local wlen="${parent[1]}" nlen="${parent[3]}" ntype="${parent[4]}" nbeg="$inest"
  ((ctx=parent[0]))
  ((wtype=parent[2]))
  ((wbegin=wlen<0?wlen:nbeg-wlen))
  ((inest=nlen<0?nlen:nbeg-nlen))

  ble-syntax/parse/tree-append "$ntype" "$nbeg"
}
function ble-syntax/parse/nest-type {
  local _var=type
  [[ $1 == -v ]] && _var="$2"
  if ((inest<0)); then
    eval "$_var="
    return 1
  else
    eval "$_var=\"\${_ble_syntax_nest[inest]##* }\""
  fi
}
## 関数 ble-syntax/parse/nest-equals
##   現在のネスト状態と前回のネスト状態が一致するか判定します。
## @var i1                     更新開始点
## @var i2                     更新終了点
## @var _tail_syntax_stat[i-i2] i2 以降の更新前状態
## @var _ble_syntax_stat[i]    新しい状態
function ble-syntax/parse/nest-equals {
  local parent_inest="$1"
  while :; do
    ((parent_inest<i1)) && return 0 # 変更していない範囲 または -1
    ((parent_inest<i2)) && return 1 # 変更によって消えた範囲

    local _onest="${_tail_syntax_nest[parent_inest-i2]}"
    local _nnest="${_ble_syntax_nest[parent_inest]}"
    [[ $_onest != $_nnest ]] && return 1

    local -a onest
    onest=($_onest)
#%if debug (
    ((onest[3]<parent_inest)) || ble-stackdump 'invalid nest' && return 0
#%)
    parent_inest="${onest[3]}"
  done
}

# _ble_syntax_word

BLE_SYNTAX_TREENODE_WIDTH=4

function ble-syntax/parse/tree-append {
  local type="$1"
  local beg="$2" end="$i"
  local len="$((end-beg))"
  ((len==0)) && return

  # 子情報・兄情報
  local ochild=-1 oprev=-1
  local j pbeg=$((wbegin>=0?wbegin:(inest>=0?inest:0)))
  for ((j=end;j>beg;j--)); do
    if [[ ${_ble_syntax_word[j-1]} ]]; then
      ochild=$((end-j))
      break
    fi
  done
  for ((j=beg;j>pbeg;j--)); do
    if [[ ${_ble_syntax_word[j-1]} ]]; then
      oprev=$((end-j))
      break
    fi
  done

  ble-syntax/parse/touch-updated-word "$i"
  _ble_syntax_word[i-1]="$type $len $ochild $oprev ${_ble_syntax_word[i-1]}"
}
function ble-syntax/parse/tree-append-word {
  local wb="$wbegin" wt="$wtype"
  ((wbegin=-1,wtype=-1))
  ble-syntax/parse/tree-append "$wt" "$wb"
}

# 属性値の変更範囲

## @var _ble_syntax_attr_umin, _ble_syntax_attr_uend は更新された文法属性の範囲を記録する。
## @var _ble_syntax_word_umin, _ble_syntax_word_umax は更新された単語の先頭位置の範囲を記録する。
##   attr については [_ble_syntax_attr_umin, _ble_syntax_attr_uend) が範囲である。
##   word については [_ble_syntax_word_umin, _ble_syntax_word_umax] が範囲である。
_ble_syntax_attr_umin=-1 _ble_syntax_attr_uend=-1
_ble_syntax_word_umin=-1 _ble_syntax_word_umax=-1
function ble-syntax/parse/touch-updated-attr {
  (((_ble_syntax_attr_umin<0||_ble_syntax_attr_umin>$1)&&(
      _ble_syntax_attr_umin=$1)))
}
function ble-syntax/parse/touch-updated-word {
#%if debug (
  (($1>0)) || ble-stackdump "invalid word position $1"
#%)
  (((_ble_syntax_word_umin<0||_ble_syntax_word_umin>$1)&&(
      _ble_syntax_word_umin=$1)))
  (((_ble_syntax_word_umax<0||_ble_syntax_word_umax<$1)&&(
      _ble_syntax_word_umax=$1)))
}

#------------------------------------------------------------------------------
# 共通の字句

function ble-syntax/parse/check-dollar {
  local rex
  if [[ $tail == '${'* ]]; then
    # ■中で許される物: 決まったパターン + 数式や文字列に途中で切り替わる事も
    if rex='^(\$\{[#!]?)([-*@#?$!0]|[1-9][0-9]*|[a-zA-Z_][a-zA-Z_0-9]*)(\[?)' && [[ $tail =~ $rex ]]; then
      # <parameter> = [-*@#?-$!0] | [1-9][0-9]* | <varname> | <varname> [ ... ] | <varname> [ <@> ]
      # <@> = * | @
      # ${<parameter>} ${#<parameter>} ${!<parameter>}
      # ${<parameter>:-<word>} ${<parameter>:=<word>} ${<parameter>:+<word>} ${<parameter>:?<word>}
      # ${<parameter>-<word>} ${<parameter>=<word>} ${<parameter>+<word>} ${<parameter>?<word>}
      # ${<parameter>:expr} ${<parameter>:expr:expr} etc
      # ${!head<@>} ${!varname[<@>]}

      # for bash-3.1 ${#arr[n]} bug
      local rematch1="${BASH_REMATCH[1]}"
      local rematch2="${BASH_REMATCH[2]}"
      local rematch3="${BASH_REMATCH[3]}"

      ble-syntax/parse/nest-push "$CTX_PARAM" '${'
      ((_ble_syntax_attr[i]=ctx,
        i+=${#rematch1},
        _ble_syntax_attr[i]=ATTR_VAR,
        i+=${#rematch2}))
      if [[ $rematch3 ]]; then
        ble-syntax/parse/nest-push "$CTX_EXPR" 'v['
        ((_ble_syntax_attr[i]=CTX_EXPR,
          i+=${#rematch3}))
      fi
      return 0
    else
      ((_ble_syntax_attr[i]=ATTR_ERR,i+=2))
      return 0
    fi
  elif [[ $tail == '$(('* ]]; then
    ((_ble_syntax_attr[i]=CTX_PARAM))
    ble-syntax/parse/nest-push "$CTX_EXPR" '(('
    ((i+=3))
    return 0
  elif [[ $tail == '$['* ]]; then
    ((_ble_syntax_attr[i]=CTX_PARAM))
    ble-syntax/parse/nest-push "$CTX_EXPR" '['
    ((i+=2))
    return 0
  elif [[ $tail == '$('* ]]; then
    ((_ble_syntax_attr[i]=CTX_PARAM))
    ble-syntax/parse/nest-push "$CTX_CMDX" '$('
    ((i+=2))
    return 0
  elif rex='^\$([-*@#?$!0_]|[1-9][0-9]*|[a-zA-Z_][a-zA-Z_0-9]*)' && [[ $tail =~ $rex ]]; then
    ((_ble_syntax_attr[i]=CTX_PARAM,
      _ble_syntax_attr[i+1]=ATTR_VAR,
      i+=${#BASH_REMATCH}))
    return 0
  fi

  return 1
}

function ble-syntax/parse/check-quotes {
  local rex

  if rex='^`([^`\]|\\(.|$))*(`?)|^'\''[^'\'']*('\''?)' && [[ $tail =~ $rex ]]; then
    ((_ble_syntax_attr[i]=ATTR_QDEL,
      _ble_syntax_attr[i+1]=CTX_QUOT,
      i+=${#BASH_REMATCH},
      _ble_syntax_attr[i-1]=${#BASH_REMATCH[3]}||${#BASH_REMATCH[4]}?ATTR_QDEL:ATTR_ERR))
    return 0
  fi

  if ((ctx!=CTX_QUOT)); then
    if rex='^(\$?")([^'"${_BLE_SYNTAX_CSPECIAL[CTX_QUOT]}"']|\\.)*("?)' && [[ $tail =~ $rex ]]; then
      if [[ ${BASH_REMATCH[3]} ]]; then
        # 終端まで行った場合
        local rematch1="${BASH_REMATCH[1]}" # for bash-3.1 ${#arr[n]} bug
        ((_ble_syntax_attr[i]=ATTR_QDEL,
          _ble_syntax_attr[i+${#rematch1}]=CTX_QUOT,
          i+=${#BASH_REMATCH},
          _ble_syntax_attr[i-1]=ATTR_QDEL))
      else
        # 中に構造がある場合
        ble-syntax/parse/nest-push "$CTX_QUOT"
        ((_ble_syntax_attr[i]=ATTR_QDEL,
          _ble_syntax_attr[i+1]=CTX_QUOT,
          i+=${#BASH_REMATCH}))
      fi
      return 0
    elif rex='^\$'\''([^'\''\]|\\(.|$))*('\''?)' && [[ $tail =~ $rex ]]; then
      ((_ble_syntax_attr[i]=ATTR_QDEL,
        _ble_syntax_attr[i+2]=CTX_QUOT,
        i+=${#BASH_REMATCH},
        _ble_syntax_attr[i-1]=${#BASH_REMATCH[3]}?ATTR_QDEL:ATTR_ERR))
      return 0
    fi
  fi

  return 1
}

function ble-syntax/parse/check-process-subst {
  # プロセス置換
  if [[ $tail == ['<>']'('* ]]; then
    ble-syntax/parse/nest-push "$CTX_CMDX" '('
    ((_ble_syntax_attr[i]=ATTR_DEL,i+=2))
    return 0
  fi

  return 1
}

function ble-syntax/parse/check-comment {
  # コメント
  if ((wbegin<i)) && local rex=$'^#[^\n]*' && [[ $tail =~ $rex ]]; then
    # 空白と同様に ctx は変えずに素通り
    ((_ble_syntax_attr[i]=ATTR_COMMENT,
      i+=${#BASH_REMATCH}))
    return 0
  else
    return 1
  fi
}

# histchars には対応していない
#   histchars を変更した時に変更するべき所:
#   - _ble_syntax_rex_histexpand.init
#   - ble-syntax/parse/check-history-expansion
#   - _BLE_SYNTAX_CSPECIAL の中の !^ の部分
_ble_syntax_rex_histexpand_event=
_ble_syntax_rex_histexpand_word=
_ble_syntax_rex_histexpand_mods=
_ble_syntax_rex_histexpand_quicksub=
function _ble_syntax_rex_histexpand.init {
  local spaces=$' \t\n' nl=$'\n'
  local rex_event='-?[0-9]+|[!#]|[^-$^*%:'"$spaces"'=?!#;&|<>()]+|\?[^?'"$nl"']*\??'
  _ble_syntax_rex_histexpand_event='^!('"$rex_event"')'

  local rex_word1='([0-9]+|[$%^])'
  local rex_wordsA=':('"$rex_word1"'?-'"$rex_word1"'?|\*|'"$rex_word1"'\*?)'
  local rex_wordsB='([$%^]?-'"$rex_word1"'?|\*|[$^%][*-]?)'
  _ble_syntax_rex_histexpand_word='('"$rex_wordsA|$rex_wordsB"')?'

  # ※本当は /s(.)([^\]|\\.)*?\1([^\]|\\.)*?\1/ 等としたいが *? は ERE にない。
  #   正しく対応しようと思ったら一回の正規表現でやろうとせずに繰り返し適用する?
  local rex_modifier=':[htrepqx&gG]|:s(/([^\/]|\\.)*){0,2}(/|$)'
  _ble_syntax_rex_histexpand_mods='('"$rex_modifier"')*'

  _ble_syntax_rex_histexpand_quicksub='\^([^\^]|\\.)*\^([^\^]|\\.)*\^'
}

_ble_syntax_rex_histexpand.init

function ble-syntax/parse/check-history-expansion {
  [[ $- == *H* ]] || return 1

  local spaces=$' \t\n'
  if [[ $tail == '!'[^"=$spaces"]* ]]; then
    ((_ble_syntax_attr[i]=ATTR_HISTX))
    if [[ $tail =~ $_ble_syntax_rex_histexpand_event ]]; then
      ((i+=${#BASH_REMATCH}))
    elif [[ $tail =~ '!'['-:0-9^$%*']* ]]; then
      ((_ble_syntax_attr[i]=ATTR_HISTX,i++))
    else
      # ErrMsg 'unrecognized event'
      ((_ble_syntax_attr[i+1]=ATTR_ERR,i+=2))
      return 0
    fi

    # word-designator
    [[ ${text:i} =~ $_ble_syntax_rex_histexpand_word ]] &&
      ((i+=${#BASH_REMATCH}))

    # modifiers
    [[ ${text:i} =~ $_ble_syntax_rex_histexpand_mods ]] &&
      ((i+=${#BASH_REMATCH}))

    # ErrMsg 'unrecognized modifier'
    [[ ${text:i} == ':'* ]] &&
      ((_ble_syntax_attr[i]=ATTR_ERR,i++))
    return 0
  elif ((i==0)) && [[ $tail == '^'* ]]; then
    ((_ble_syntax_attr[i]=ATTR_HISTX))
    if [[ $tail =~ $_ble_syntax_rex_histexpand_quicksub ]]; then
      ((i+=${#BASH_REMATCH}))

      # modifiers
      [[ ${text:i} =~ $_ble_syntax_rex_histexpand_mods ]] &&
        ((i+=${#BASH_REMATCH}))

      # ErrMsg 'unrecognized modifier'
      [[ ${text:i} == ':'* ]] &&
        ((_ble_syntax_attr[i]=ATTR_ERR,i++))
      return 0
    else
      # 末端まで
      ((i+=${#tail}))
      return 0
    fi
  fi

  return 1
}


#------------------------------------------------------------------------------
# 文脈: 各種文脈

_BLE_SYNTAX_FCTX=()
_BLE_SYNTAX_FEND=()

_BLE_SYNTAX_FCTX[CTX_QUOT]=ble-syntax/parse/ctx-quot
function ble-syntax/parse/ctx-quot {
  # 文字列の中身
  local rex
  if rex='^([^'"${_BLE_SYNTAX_CSPECIAL[ctx]}"']|\\.)+' && [[ $tail =~ $rex ]]; then
    ((_ble_syntax_attr[i]=ctx,
      i+=${#BASH_REMATCH}))
    return 0
  elif [[ $tail == '"'* ]]; then
    ((_ble_syntax_attr[i]=ATTR_QDEL,
      i+=1))
    ble-syntax/parse/nest-pop
    return 0
  elif ble-syntax/parse/check-quotes; then
    return 0
  elif ble-syntax/parse/check-dollar; then
    return 0
  elif [[ $tail == ['!^']* ]]; then
    ble-syntax/parse/check-history-expansion ||
      ((_ble_syntax_attr[i]=ctx,i++))
    return 0
  fi

  return 1
}

_BLE_SYNTAX_FCTX[CTX_PARAM]=ble-syntax/parse/ctx-param
_BLE_SYNTAX_FCTX[CTX_PWORD]=ble-syntax/parse/ctx-pword
function ble-syntax/parse/ctx-param {
  # パラメータ展開 - パラメータの直後

  if [[ $tail == :[^-?=+]* ]]; then
    ((_ble_syntax_attr[i]=CTX_EXPR,
      ctx=CTX_EXPR,i++))
    return 0
  elif [[ $tail == '}'* ]]; then
    ((_ble_syntax_attr[i]=_ble_syntax_attr[inest]))
    ((i+=1))
    ble-syntax/parse/nest-pop
    return 0
  else
    ((ctx=CTX_PWORD))
    ble-syntax/parse/ctx-pword
    return
  fi
}
function ble-syntax/parse/ctx-pword {
  # パラメータ展開 - word 部
  local rex
  if rex='^([^'"${_BLE_SYNTAX_CSPECIAL[ctx]}"']|\\.)+' && [[ $tail =~ $rex ]]; then
    ((_ble_syntax_attr[i]=ctx,
      i+=${#BASH_REMATCH}))
    return 0
  elif [[ $tail == '}'* ]]; then
    ((_ble_syntax_attr[i]=_ble_syntax_attr[inest]))
    ((i+=1))
    ble-syntax/parse/nest-pop
    return 0
  elif ble-syntax/parse/check-quotes; then
    return 0
  elif ble-syntax/parse/check-dollar; then
    return 0
  elif [[ $tail == ['!^']* ]]; then
    ble-syntax/parse/check-history-expansion ||
      ((_ble_syntax_attr[i]=ctx,i++))
    return 0
  fi

  return 1
}

_BLE_SYNTAX_FCTX[CTX_EXPR]=ble-syntax/parse/ctx-expr
function ble-syntax/parse/ctx-expr {
  # 式の中身
  local rex

  if rex='^([^'"${_BLE_SYNTAX_CSPECIAL[ctx]}"']|\\.)+' && [[ $tail =~ $rex ]]; then
    ((_ble_syntax_attr[i]=ctx,
      i+=${#BASH_REMATCH}))
    return 0
  elif rex='^[][()}]' && [[ $tail =~ $rex ]]; then
    if [[ ${BASH_REMATCH[0]} == ')' ]]; then
      local type
      ble-syntax/parse/nest-type -v type
      if [[ $type == '((' ]]; then
        if [[ $tail == '))'* ]]; then
          ((_ble_syntax_attr[i]=_ble_syntax_attr[inest]))
          ((i+=2))
          ble-syntax/parse/nest-pop
        else
          ((_ble_syntax_attr[i]=ATTR_ERR,
            i+=1))
          ble-syntax/parse/nest-pop
        fi
        return 0
      elif [[ $type == '(' ]]; then
        ((_ble_syntax_attr[i]=ctx,i+=1))
        ble-syntax/parse/nest-pop
        return 0
      else
        return 1
      fi
    elif [[ ${BASH_REMATCH[0]} == ']' ]]; then
      local type
      ble-syntax/parse/nest-type -v type
      if [[ $type == '[' ]]; then
        # ((a[...]=123)) や $[...] などの場合。
        ((_ble_syntax_attr[i]=_ble_syntax_attr[inest]))
        ((i++))
        ble-syntax/parse/nest-pop
        return 0
      elif [[ $type == 'a[' ]]; then
        if [[ $tail == ']='* ]]; then
          # a[...]= の場合。配列代入
          ble-syntax/parse/nest-pop
          ((_ble_syntax_attr[i]=CTX_EXPR,
            i+=2))
        else
          # a[...]... という唯のコマンドの場合。
          ((_ble_syntax_attr[i]=CTX_EXPR,i++))
          ble-syntax/parse/nest-pop
          ((ctx=CTX_CMDI,wtype=CTX_CMDI))

          # 入れ子構造などの情報が飛んでしまうので削除はしない。
          # if ((wbegin>=0)); then
          #   ble-syntax/parse/touch-updated-attr "$wbegin"

          #   # 式としての解釈を取り消し。
          #   local j
          #   for ((j=wbegin+1;j<i;j++)); do
          #     _ble_syntax_stat[j]=
          #     _ble_syntax_word[j-1]=
          #     _ble_syntax_attr[j]=
          #   done

          #   # コマンド
          #   ((_ble_syntax_attr[wbegin]=CTX_CMDI))
          # fi
        fi
        return 0
      elif [[ $type == 'v[' ]]; then
        # ${v[]...} などの場合。
        ((_ble_syntax_attr[i]=CTX_EXPR,
          i++))
        ble-syntax/parse/nest-pop
        return 0
      else
        return 1
      fi
    elif [[ ${BASH_REMATCH[0]} == '}' ]]; then
      local type
      ble-syntax/parse/nest-type -v type
      if [[ $type == '${' ]]; then
        ((_ble_syntax_attr[i]=_ble_syntax_attr[inest]))
        ((i++))
        ble-syntax/parse/nest-pop
        return 0
      else
        return 1
      fi
    else
      ble-syntax/parse/nest-push "$CTX_EXPR" "${BASH_REMATCH[0]}"
      ((_ble_syntax_attr[i]=ctx,
        i+=${#BASH_REMATCH}))
      return 0
    fi
  elif ble-syntax/parse/check-quotes; then
    return 0
  elif ble-syntax/parse/check-dollar; then
    return 0
  elif [[ $tail == ['!^']* ]]; then
    # 恐ろしい事に数式中でも履歴展開が有効…。
    ble-syntax/parse/check-history-expansion ||
      ((_ble_syntax_attr[i]=ctx,i++))
    return 0
  fi

  return 1
}

#------------------------------------------------------------------------------
# 文脈: コマンドライン

_BLE_SYNTAX_FCTX[CTX_ARGX]=ble-syntax/parse/ctx-command
_BLE_SYNTAX_FCTX[CTX_ARGX0]=ble-syntax/parse/ctx-command
_BLE_SYNTAX_FCTX[CTX_CMDX]=ble-syntax/parse/ctx-command
_BLE_SYNTAX_FCTX[CTX_CMDX1]=ble-syntax/parse/ctx-command
_BLE_SYNTAX_FCTX[CTX_CMDXF]=ble-syntax/parse/ctx-command
_BLE_SYNTAX_FCTX[CTX_CMDXV]=ble-syntax/parse/ctx-command
_BLE_SYNTAX_FCTX[CTX_ARGI]=ble-syntax/parse/ctx-command
_BLE_SYNTAX_FCTX[CTX_CMDI]=ble-syntax/parse/ctx-command
_BLE_SYNTAX_FCTX[CTX_VRHS]=ble-syntax/parse/ctx-command
_BLE_SYNTAX_FEND[CTX_CMDI]=ble-syntax/parse/ctx-command/check-word-end
_BLE_SYNTAX_FEND[CTX_ARGI]=ble-syntax/parse/ctx-command/check-word-end
_BLE_SYNTAX_FEND[CTX_VRHS]=ble-syntax/parse/ctx-command/check-word-end

## 関数 ble-syntax/parse/ctx-command/check-word-end
## @var[in,out] ctx
## @var[in,out] wbegin
## @var[in,out] 他
function ble-syntax/parse/ctx-command/check-word-end {
  # 単語の中にいない時は抜ける
  ((wbegin<0)) && return 1

  # 未だ続きがある場合は抜ける
  [[ ${text:i:1} == [^"$_BLE_SYNTAX_CSPACE;|&<>()"] ]] && return 1

  local wbeg="$wbegin" wlen="$((i-wbegin))" wend="$i"
  local word="${text:wbegin:wlen}"

  ble-syntax/parse/tree-append-word

  if ((ctx==CTX_CMDI)); then
    case "$word" in
    ('[[')
      # 条件コマンド開始
      ble-syntax/parse/touch-updated-attr "$wbeg"
      ((_ble_syntax_attr[wbeg]=ATTR_DEL,
        ctx=CTX_ARGX0))

      i="$wbeg" ble-syntax/parse/nest-push "$CTX_VALX" '[['
      return 0 ;;
    (['!{']|'time'|'do'|'if'|'then'|'else'|'while'|'until')
      ((ctx=CTX_CMDX1)) ;;
    ('for')
      ((ctx=CTX_CMDXF)) ;;
    ('}'|'done'|'fi'|'esac')
      ((ctx=CTX_ARGX0)) ;;
    (*)
      # 関数定義である可能性を考え stat を置かず読み取る
      if rex='^([ 	]*)(\([ 	]*(\))?)?' && [[ ${text:i} =~ $rex ]]; then

        # for bash-3.1 ${#arr[n]} bug
        local rematch1="${BASH_REMATCH[1]}"
        local rematch2="${BASH_REMATCH[2]}"

        if [[ ${BASH_REMATCH[3]} ]]; then
          # 関数定義 (単語の種類を変更)
          _ble_syntax_word[i-1]="$ATTR_FUNCDEF ${_ble_syntax_word[i-1]#* }"

          ((_ble_syntax_attr[i]=CTX_CMDX1,
            _ble_syntax_attr[i+${#rematch1}]=ATTR_DEL,
            ctx=CTX_CMDX1,
            i+=${#BASH_REMATCH}))
        elif [[ ${BASH_REMATCH[2]} ]]; then
          # 括弧が閉じていない場合:
          #   仕方がないのでサブシェルと思って取り敢えず解析する
          ((_ble_syntax_attr[i]=CTX_ARGX0,
            i+=${#rematch1},
            _ble_syntax_attr[i]=ATTR_ERR,
            ctx=CTX_ARGX0))
          ble-syntax/parse/nest-push "$CTX_CMDX1" '('
          ((${#rematch2}>=2&&(_ble_syntax_attr[i+1]=CTX_CMDX1),
            i+=${#rematch2}))
          return 0
        else
          # 恐らくコマンド
          ((_ble_syntax_attr[i]=CTX_ARGX,
            ctx=CTX_ARGX,
            i+=${#BASH_REMATCH}))
        fi
      fi ;;
    esac
  elif ((ctx==CTX_ARGI)); then
    # case "$word" in
    # (']]')
    #   # 条件コマンド終了
    #   local type
    #   ble-syntax/parse/nest-type -v type
    #   if [[ $type == '[[' ]]; then
    #     ble-syntax/parse/touch-updated-attr "$wbeg"
    #     ((_ble_syntax_attr[wbeg]=ATTR_CMD_KEYWORD))
    #     ble-syntax/parse/nest-pop
    #     return 0
    #   else
    #     ((ctx=CTX_ARGX0))
    #   fi ;;
    # (*)
    #   ((ctx=CTX_ARGX)) ;;
    # esac
    ((ctx=CTX_ARGX))
  elif ((ctx==CTX_VRHS)); then
    ((ctx=CTX_CMDXV))
  fi

  return 0
}

function ble-syntax/parse/ctx-command {
  # コマンド・引数部分
  local rex

  local rex_delimiters="^[$_BLE_SYNTAX_CSPACE;|&<>()]"
  local rex_redirect='^((\{[a-zA-Z_][a-zA-Z_0-9]+\}|[0-9]+)?(&?>>?|<>?|[<>]&))['"$_BLE_SYNTAX_CSPACE"']*'
  if [[ ( $tail =~ $rex_delimiters || $wbegin -lt 0 && $tail =~ $rex_redirect ) && $tail != ['<>']'('* ]]; then
#%if debug (
    ((ctx==CTX_ARGX||ctx==CTX_ARGX0||
         ctx==CTX_CMDX||ctx==CTX_CMDXF||
         ctx==CTX_CMDX1||ctx==CTX_CMDXV)) || ble-stackdump "invalid ctx=$ctx @ i=$i"
    ((wbegin<0&&wtype<0)) || ble-stackdump "invalid word-context (wtype=$wtype wbegin=$wbegin) on non-word char."
#%)

    if rex="^[$_BLE_SYNTAX_CSPACE]+" && [[ $tail =~ $rex ]]; then
      # 空白 (ctx はそのままで素通り)
      ((_ble_syntax_attr[i]=ctx,i+=${#BASH_REMATCH}))
      ((ctx==CTX_ARGX||ctx==CTX_ARGX0||ctx==CTX_CMDXV)) && [[ ${BASH_REMATCH[0]} =~ $'\n' ]] && ((ctx=CTX_CMDX))
      return 0
    elif [[ $tail =~ $rex_redirect ]]; then
      # リダイレクト (& 単体の解釈より優先する)

      # for bash-3.1 ${#arr[n]} bug ... 一旦 rematch1 に入れてから ${#rematch1} で文字数を得る。
      local rematch1="${BASH_REMATCH[1]}"
      if [[ $rematch1 == *'&' ]]; then
        ble-syntax/parse/nest-push "$CTX_RDRD" "$rematch1"
      else
        ble-syntax/parse/nest-push "$CTX_RDRF" "$rematch1"
      fi
      ((_ble_syntax_attr[i]=ATTR_DEL,
        _ble_syntax_attr[i+${#rematch1}]=CTX_ARGX,
        i+=${#BASH_REMATCH}))
      return 0

      #■リダイレクト&プロセス置換では直前の ctx を覚えて置いて後で復元する。
    elif rex='^;;&?|^;&|^(&&|\|[|&]?)|^[;&]' && [[ $tail =~ $rex ]]; then
      # 制御演算子 && || | & ; |& ;; ;;&

      # for bash-3.1 ${#arr[n]} bug
      local rematch1="${BASH_REMATCH[1]}"
      ((_ble_syntax_attr[i]=ctx==CTX_ARGX||ctx==CTX_ARGX0||ctx==CTX_CMDXV?ATTR_DEL:ATTR_ERR,
        ctx=${#rematch1}?CTX_CMDX1:CTX_CMDX,
        i+=${#BASH_REMATCH}))
      #■;& ;; ;;& の次に来るのは CTX_CMDX ではなくて CTX_CASE? 的な物では?
      #■;& ;; ;;& の場合には CTX_ARGX CTX_CMDXV に加え CTX_CMDX でも ERR ではない。
      return 0
    elif rex='^\(\(?' && [[ $tail =~ $rex ]]; then
      # サブシェル (, 算術コマンド ((
      local m="${BASH_REMATCH[0]}"
      ((_ble_syntax_attr[i]=(ctx==CTX_CMDX||ctx==CTX_CMDX1||ctx==CTX_CMDXF&&${#m}==2)?ATTR_DEL:ATTR_ERR))
      ((ctx=CTX_ARGX0))
      ble-syntax/parse/nest-push "$((${#m}==1?CTX_CMDX1:CTX_EXPR))" "$m"
      ((i+=${#m}))
      return 0
    elif [[ $tail == ')'* ]]; then
      ble-syntax/parse/nest-type -v type
      local attr=
      if [[ $type == '(' ]]; then
        # ( sub shell )
        # <( process substitution )
        # func ( invalid )
        ((attr=ATTR_DEL))
      elif [[ $type == '$(' ]]; then
        # $(command substitution)
        ((attr=CTX_PARAM))
      fi

      if [[ $attr ]]; then
        ((_ble_syntax_attr[i]=(ctx==CTX_CMDX||ctx==CTX_ARGX||ctx==CTX_ARGX0||ctx==CTX_CMDXV)?attr:ATTR_ERR,
          i+=1))
        ble-syntax/parse/nest-pop
        return 0
      fi
    else
      return 1
    fi
  fi

  if ble-syntax/parse/check-comment; then
    return 0
  fi

  local unexpectedWbegin=-1
  if ((wbegin<0)); then
    # case CTX_ARGX | CTX_ARGX0 | CTX_CMDXF
    #   ctx=CTX_ARGI
    # case CTX_CMDX | CTX_CMDX1 | CTX_CMDXV
    #   ctx=CTX_CMDI
    # case CTX_ARGI | CTX_CMDI | CTX_VRHS
    #   エラー...
    ((ctx==CTX_ARGX0&&(unexpectedWbegin=i),
      ctx=(ctx==CTX_ARGX||ctx==CTX_ARGX0||ctx==CTX_CMDXF)?CTX_ARGI:CTX_CMDI,
      wbegin=i,wtype=ctx))
  fi

#%if debug (
  ((ctx==CTX_CMDI||ctx==CTX_ARGI||ctx==CTX_VRHS)) || ble-stackdump 2
#%)

  local flagConsume=0
  if ((wbegin==i&&ctx==CTX_CMDI)) && rex='^[a-zA-Z_][a-zA-Z_0-9]*([=[]|\+=)' && [[ $tail =~ $rex ]]; then
    # for bash-3.1 ${#arr[n]} bug
    local rematch1="${BASH_REMATCH[1]}"

    ((wtype=ATTR_VAR,
      _ble_syntax_attr[i]=ATTR_VAR,
      i+=${#BASH_REMATCH},
      _ble_syntax_attr[i-${#rematch1}]=CTX_EXPR,
      ctx=CTX_VRHS))
    if [[ $rematch1 == '[' ]]; then
      # arr[
      i=$((i-1)) ble-syntax/parse/nest-push "$CTX_EXPR" 'a['
    elif [[ ${text:i} == '('* ]]; then
      # var=( var+=(
      ((ctx=CTX_CMDXV,wbegin=-1,wtype=-1)) # pop したら直ぐにコマンドが来て良い
      ble-syntax/parse/nest-push "$CTX_VALX" 'A('
      ((_ble_syntax_attr[i]=ATTR_DEL,i+=1))
    fi
    flagConsume=1
  elif rex='^([^'"${_BLE_SYNTAX_CSPECIAL[CTX_ARGI]}"']|\\.)+' && [[ $tail =~ $rex ]]; then
    ((_ble_syntax_attr[i]=ctx,
      i+=${#BASH_REMATCH}))
    flagConsume=1
  elif ble-syntax/parse/check-process-subst; then
    flagConsume=1
  elif ble-syntax/parse/check-quotes; then
    flagConsume=1
  elif ble-syntax/parse/check-dollar; then
    flagConsume=1
  elif [[ $tail == ['!^']* ]]; then
    ble-syntax/parse/check-history-expansion ||
      ((_ble_syntax_attr[i]=ctx,i++))
    flagConsume=1
  fi

  if ((flagConsume)); then
    if ((unexpectedWbegin>=0)); then
      ble-syntax/parse/touch-updated-attr "$unexpectedWbegin"
      ((_ble_syntax_attr[unexpectedWbegin]=ATTR_ERR))
    fi
    return 0
  else
    return 1
  fi
}

#------------------------------------------------------------------------------
# 文脈: 値リスト、条件コマンド
#
#   値リストと条件コマンドの文法は、 &<>() 等の文字に対して結構違う。
#   分離した方が良いのではないか?
#

_BLE_SYNTAX_FCTX[CTX_VALX]=ble-syntax/parse/ctx-values
_BLE_SYNTAX_FCTX[CTX_VALI]=ble-syntax/parse/ctx-values
_BLE_SYNTAX_FEND[CTX_VALI]=ble-syntax/parse/ctx-values/check-word-end

## 関数 ble-syntax/parse/ctx-values/check-word-end
function ble-syntax/parse/ctx-values/check-word-end {
  # 単語の中にいない時は抜ける
  ((wbegin<0)) && return 1

  # 未だ続きがある場合は抜ける
  [[ ${text:i:1} == [^"$_BLE_SYNTAX_CSPACE;|&<>()"] ]] && return 1

  local wbeg="$wbegin" wlen="$((i-wbegin))" wend="$i"
  local word="${text:wbegin:wlen}"

  ble-syntax/parse/tree-append-word

  ble-assert '((ctx==CTX_VALI))' 'invalid context'
  case "$word" in
  (']]')
    # 条件コマンド終了
    local type
    ble-syntax/parse/nest-type -v type
    if [[ $type == '[[' ]]; then
      ble-syntax/parse/touch-updated-attr "$wbeg"
      ((_ble_syntax_attr[wbeg]=ATTR_CMD_KEYWORD))
      ble-syntax/parse/nest-pop
      return 0
    else
      ((ctx=CTX_VALX))
    fi ;;
  (*)
    ((ctx=CTX_VALX)) ;;
  esac

  return 0
}

function ble-syntax/parse/ctx-values {
  # コマンド・引数部分
  local rex

  local rex_delimiters="^[$_BLE_SYNTAX_CSPACE;|&<>()]"
  if [[ $tail =~ $rex_delimiters && $tail != ['<>']'('* ]]; then
#%if debug (
    ((ctx==CTX_VALX)) || ble-stackdump "invalid ctx=$ctx @ i=$i"
    ((wbegin<0&&wtype<0)) || ble-stackdump "invalid word-context (wtype=$wtype wbegin=$wbegin) on non-word char."
#%)

    if rex="^[$_BLE_SYNTAX_CSPACE]+" && [[ $tail =~ $rex ]]; then
      # 空白 (ctx はそのままで素通り)
      ((_ble_syntax_attr[i]=ctx,i+=${#BASH_REMATCH}))
      return 0
    elif [[ $tail == ')'* ]]; then
      local type
      ble-syntax/parse/nest-type -v type
      if [[ $type == 'A(' ]]; then
        # 配列定義の終了
        ((_ble_syntax_attr[i++]=ATTR_DEL))
        ble-syntax/parse/nest-pop
        return 0
      fi
      # そのまま単語へ(?)
    elif [[ $type == ';'* ]]; then
      ((_ble_syntax_attr[i++]=ATTR_ERR))
      return 0
    else
      local type
      ble-syntax/parse/nest-type -v type
      if [[ $type == 'A(' ]]; then
        ((_ble_syntax_attr[i++]=ATTR_ERR))
      else
        ((_ble_syntax_attr[i++]=ATTR_VALI))
      fi
      return 0
    fi
  fi

  if ble-syntax/parse/check-comment; then
    return 0
  fi

  if ((wbegin<0)); then
    ((ctx=CTX_VALI,wbegin=i,wtype=ctx))
  fi

#%if debug (
  ble-assert '((ctx==CTX_VALI))' "invalid context ctx=$ctx"
#%)

  if rex='^([^'"${_BLE_SYNTAX_CSPECIAL[CTX_ARGI]}"']|\\.)+' && [[ $tail =~ $rex ]]; then
    ((_ble_syntax_attr[i]=ctx,
      i+=${#BASH_REMATCH}))
    return 0
  elif ble-syntax/parse/check-process-subst; then
    return 0
  elif ble-syntax/parse/check-quotes; then
    return 0
  elif ble-syntax/parse/check-dollar; then
    return 0
  elif [[ $tail == ['!^']* ]]; then
    ble-syntax/parse/check-history-expansion ||
      ((_ble_syntax_attr[i]=ctx,i++))
    return 0
  else
    local type
    ble-syntax/parse/nest-type -v type
    if [[ $type == '[[' ]]; then
      # 条件コマンドの時は $ や ) 等を許す。。
      ((_ble_syntax_attr[i]=ctx,i++))
      return 0
    fi
  fi

  return 1
}

#------------------------------------------------------------------------------
# 文脈: リダイレクト

_BLE_SYNTAX_FCTX[CTX_RDRF]=ble-syntax/parse/ctx-redirect
_BLE_SYNTAX_FCTX[CTX_RDRD]=ble-syntax/parse/ctx-redirect
_BLE_SYNTAX_FEND[CTX_RDRF]=ble-syntax/parse/ctx-redirect/check-word-end
_BLE_SYNTAX_FEND[CTX_RDRD]=ble-syntax/parse/ctx-redirect/check-word-end
function ble-syntax/parse/ctx-redirect/check-word-begin {
  if ((wbegin<0)); then
    # ※ここで ctx==CTX_RDRF か ctx==CTX_RDRD かの情報が使われるので
    #   CTX_RDRF と CTX_RDRD は異なる二つの文脈として管理している。
    ((wbegin=i,wtype=ctx))
    ble-syntax/parse/touch-updated-word "$i"
  fi
}
function ble-syntax/parse/ctx-redirect/check-word-end {
  # 単語の中にいない時は抜ける
  ((wbegin<0)) && return 1

  # 未だ続きがある場合は抜ける
  local tail="${text:i}"
  [[ $tail == [^"$_BLE_SYNTAX_CSPACE;|&<>()"]* || $tail == ['<>']'('* ]] && return 1

  # 単語の登録
  ble-syntax/parse/tree-append-word

  # pop
  ble-syntax/parse/nest-pop
#%if debug (
  # ここで終端の必要のある ctx (CTX_CMDI や CTX_ARGI, CTX_VRHS など) になる事は無い。
  # 何故なら push した時は CMDX か ARGX の文脈にいたはずだから。
  ((ctx!=CTX_CMDI&&ctx!=CTX_ARGI&&ctx!=CTX_VRHS)) || ble-stackdump "invalid ctx=$ctx after nest-pop"
#%)
  return 0
}
function ble-syntax/parse/ctx-redirect {
  local rex

  local rex_delimiters="^[$_BLE_SYNTAX_CSPACE;|&<>()]"
  local rex_redirect='^((\{[a-zA-Z_][a-zA-Z_0-9]+\}|[0-9]+)?(&?>>?|<>?|[<>]&))['"$_BLE_SYNTAX_CSPACE"']*'
  if [[ ( $tail =~ $rex_delimiters || $wbegin -lt 0 && $tail =~ $rex_redirect ) && $tail != ['<>']'('* ]]; then
    ((_ble_syntax_attr[i-1]=ATTR_ERR))
    ble-syntax/parse/nest-pop
    return 1
  fi

  # 単語開始の設置
  ble-syntax/parse/ctx-redirect/check-word-begin

  if rex='^([^'"${_BLE_SYNTAX_CSPECIAL[CTX_ARGI]}"']|\\.)+' && [[ $tail =~ $rex ]]; then
    ((_ble_syntax_attr[i]=ctx,
      i+=${#BASH_REMATCH}))
    return 0
  elif ble-syntax/parse/check-process-subst; then
    return 0;
  elif ble-syntax/parse/check-quotes; then
    return 0
  elif ble-syntax/parse/check-dollar; then
    return 0
  elif [[ $tail == ['!^']* ]]; then
    ble-syntax/parse/check-history-expansion ||
      ((_ble_syntax_attr[i]=ctx,i++))
    return 0
  fi

  return 1
}

#------------------------------------------------------------------------------
# 解析部

_ble_syntax_dbeg=-1 _ble_syntax_dend=-1

## @fn ble-syntax/parse text beg end
##
## @param[in]     text
##   解析対象の文字列を指定する。
##
## @param[in]     beg                text変更範囲 開始点 (既定値 = text先頭)
## @param[in]     end                text変更範囲 終了点 (既定値 = text末端)
## @param[in]     end0               長さが変わった時用 (既定値 = end)
##   これらの引数はtextに変更があった場合にその範囲を伝達するのに用いる。
##
## @var  [in,out] _ble_syntax_dbeg   解析予定範囲 開始点 (初期値 -1 = 解析予定無し)
## @var  [in,out] _ble_syntax_dend   解析予定範囲 終了点 (初期値 -1 = 解析予定無し)
##   これらの変数はどの部分を解析する必要があるかを記録している。
##   beg end beg2 end2 を用いてtextの変更範囲を指定しても、
##   その変更範囲に対する解析を即座に完了させる訳ではなく逐次更新していく。
##   ここには前回の parse 呼出でやり残した解析範囲の情報が格納される。
##
## @var  [in,out] _ble_syntax_stat[] (内部使用) 解析途中状態を記録
## @var  [in,out] _ble_syntax_nest[] (内部使用) 入れ子の構造を記録
## @var  [in,out] _ble_syntax_attr[] 各文字の属性
## @var  [in,out] _ble_syntax_word[] シェル単語の情報を記録
##   これらの変数には解析結果が格納される。
##
## @var  [in,out] _ble_syntax_attr_umin
## @var  [in,out] _ble_syntax_attr_uend
## @var  [in,out] _ble_syntax_word_umin
## @var  [in,out] _ble_syntax_word_umax
##   今回の呼出によって文法的な解釈の変更が行われた範囲を更新します。
##
function ble-syntax/parse {
  local -r text="$1"
  local -r beg="${2:-0}" end="${3:-${#text}}"
  local -r end0="${4:-$end}"
  ((end==beg&&end0==beg&&_ble_syntax_dbeg<0)) && return

  _ble_syntax_text="$text"

  # 解析予定範囲の更新
  local -ir iN="${#text}" shift=end-end0
  local i1 i2 flagSeekStat=0
  ((i1=_ble_syntax_dbeg,i1>=end0&&(i1+=shift),
    i2=_ble_syntax_dend,i2>=end0&&(i2+=shift),
    (i1<0||beg<i1)&&(i1=beg,flagSeekStat=1),
    (i2<0||i2<end)&&(i2=end),
    (i2>iN)&&(i2=iN)))
  if ((flagSeekStat)); then
    # beg より前の最後の stat の位置まで戻る
    while ((i1>0)) && ! [[ ${_ble_syntax_stat[--i1]} ]]; do :;done
  fi
#%if debug (
  ((0<=beg&&beg<=end&&end<=iN&&beg<=end0)) || ble-stackdump "X1 0 <= $beg <= $end <= $iN, $beg <= $end0"
  ((0<=i1&&i1<=beg&&end<=i2&&i2<=iN)) || ble-stackdump "X2 0 <= $i1 <= $beg <= $end <= $i2 <= $iN"
#%)

  # shift (shift は毎回やり切る。途中状態で抜けたりはしない)
  local rex_word_data='^^[0-9]+[[:space:]]'
  local i j j2 jwbeg jnbeg jwlen jnlen
  local -a stat nest word
  for ((i=i2,j=j2=i2-shift;i<=iN;i++,j++)); do
    # 注意: データの範囲
    #   stat[i]   は i in [0,iN]
    #   attr[i]   は i in [0,iN)
    #   word[i-1] は i in (0,iN]
    if [[ ${_ble_syntax_stat[j]} ]]; then
      # (1) shift の修正
      # (2) 無効になった stat/word の削除

      stat=(${_ble_syntax_stat[j]})
      ((jwlen=stat[1]))
      ((jnlen=stat[3]))
      ((jwbeg=jwlen<0?-1:j-jwlen,
        jnbeg=jnlen<0?-1:j-jnlen))

      # dirty 拡大の代わりに単に stat 内容の削除を実行する。dirty 拡大の連鎖は考えない。
      if ((i1<=jwbeg&&jwbeg<=j2||i1<=jnbeg&&jnbeg<=j2)); then
        _ble_syntax_stat[j]=
      elif ((shift!=0)); then
        # shift 補正
        ((0<=jwbeg&&jwbeg<beg)) && ((stat[1]+=shift))
        ((0<=jnbeg&&jnbeg<beg)) && ((stat[3]+=shift))
        # ※bash-3.2 では、bug で分岐内で配列を参照すると必ずそちらに分岐してしまう。
        #   そのため一つの算術式にまとめると失敗する。必ず shift が加算されてしまう。
        _ble_syntax_stat[j]="${stat[*]}"
      fi
    fi

    if ((j>0)) && [[ ${_ble_syntax_word[j-1]} =~ $rex_word_data ]]; then
      word=(${_ble_syntax_word[j-1]})
      ((jwbeg=j-word[1]))

      if ((jwbeg<=end0)); then
        # 中身が書き換わった時。
        # dirty 拡大の代わりに _ble_syntax_word_umax に登録するに留める。
        ble-syntax/parse/touch-updated-word "$j"

        # 単語の長さの変更
        if ((shift!=0)); then
          ((word[1]=i-(jwbeg<beg?jwbeg:end)))
          _ble_syntax_word[j-1]="${word[*]}"
        fi
      fi
    fi

    # stat の先頭以外でも nest-push している
    #   @ ctx-command/check-word-begin の "関数名 ( " にて。
    if [[ ${_ble_syntax_nest[j]} ]]; then
      if ((shift!=0)) && ((i<iN)); then
        nest=(${_ble_syntax_nest[j]})
        ((jwlen=nest[1]))
        ((jnlen=nest[3]))
        ((jwlen>=0&&j-jwlen>=end0)) && ((nest[1]+=shift))
        ((jnlen>=0&&j-jnlen>=end0)) && ((nest[3]+=shift))
        _ble_syntax_nest[j]="${nest[*]}"
      fi
    fi
  done
  if ((shift!=0)); then
    # 更新範囲の shift
    ((_ble_syntax_attr_umin>=end0&&(_ble_syntax_attr_umin+=shift),
      _ble_syntax_attr_uend>end0&&(_ble_syntax_attr_uend+=shift),
      _ble_syntax_word_umin>=end0&&(_ble_syntax_word_umin+=shift),
      _ble_syntax_word_umax>=end0&&(_ble_syntax_word_umax+=shift)))

    # shift によって単語が潰れた時
    ((_ble_syntax_word_umin==0&&
         ++_ble_syntax_word_umin>_ble_syntax_word_umax&&
         (_ble_syntax_word_umin=_ble_syntax_word_umax=-1)))
  fi
  # .ble-line-info.draw-text "diry-range $beg-$end extended-dirty-range $i1-$i2"


  # 解析途中状態の復元
  local _stat="${_ble_syntax_stat[i1]}"
  local -a stat
  local ctx wbegin wtype inest
  if [[ $_stat ]]; then
    stat=($_stat)
    local wlen="${stat[1]}" nlen="${stat[3]}"
    ctx="${stat[0]}"
    wbegin="$((wlen<0?-1:i1-wlen))"
    wtype="${stat[2]}"
    inest="$((nlen<1?-1:i1-nlen))"
  else
    # 初期値
    ctx="$CTX_CMDX"     ##!< 現在の解析の文脈
    wbegin=-1           ##!< シェル単語内にいる時、シェル単語の開始位置
    wtype=-1            ##!< シェル単語内にいる時、シェル単語の種類
    inest=-1            ##!< 入れ子の時、親の開始位置
  fi

  # 前回までに解析が終わっている部分 [0,i1), [i2,iN)
  local -a _tail_syntax_stat _tail_syntax_word _tail_syntax_nest _tail_syntax_attr
  _tail_syntax_stat=("${_ble_syntax_stat[@]:j2:iN-i2+1}")
  _tail_syntax_word=("${_ble_syntax_word[@]:j2:iN-i2}")
  _tail_syntax_nest=("${_ble_syntax_nest[@]:j2:iN-i2}")
  _tail_syntax_attr=("${_ble_syntax_attr[@]:j2:iN-i2}")
  _ble_util_array_prototype.reserve $iN
  _ble_syntax_stat=("${_ble_syntax_stat[@]::i1}" "${_ble_util_array_prototype[@]:i1:iN-i1}") # 再開用データ
  _ble_syntax_word=("${_ble_syntax_word[@]::i1}" "${_ble_util_array_prototype[@]:i1:iN-i1}") # 単語
  _ble_syntax_nest=("${_ble_syntax_nest[@]::i1}" "${_ble_util_array_prototype[@]:i1:iN-i1}") # 入れ子の親
  _ble_syntax_attr=("${_ble_syntax_attr[@]::i1}" "${_ble_util_array_prototype[@]:i1:iN-i1}") # 文脈・色とか

  # 解析
  for ((i=i1;i<iN;)); do
    local _stat="$ctx $((wbegin<0?wbegin:i-wbegin)) $wtype $((inest<0?inest:i-inest))"
    if ((i>=i2)) && [[ ${_tail_syntax_stat[i-i2]} == $_stat ]]; then
      if ble-syntax/parse/nest-equals "$inest"; then

        # 前回の解析と同じ状態になった時 → 残りは前回の結果と同じ
        _ble_syntax_stat=("${_ble_syntax_stat[@]::i}" "${_tail_syntax_stat[@]:i-i2}")
        _ble_syntax_word=("${_ble_syntax_word[@]::i}" "${_tail_syntax_word[@]:i-i2}")
        _ble_syntax_nest=("${_ble_syntax_nest[@]::i}" "${_tail_syntax_nest[@]:i-i2}")
        _ble_syntax_attr=("${_ble_syntax_attr[@]::i}" "${_tail_syntax_attr[@]:i-i2}")
        break
      fi
    fi
    _ble_syntax_stat[i]="$_stat"
    local tail="${text:i}"

    # 処理
    "${_BLE_SYNTAX_FCTX[ctx]}" || ((_ble_syntax_attr[i]=ATTR_ERR,i++))

    # nest-pop で CMDI/ARGI になる事もあるし、
    # また単語終端な文字でも FCTX が失敗する事もある (unrecognized な場合) ので、
    # (FCTX の中や直後ではなく) ここで単語終端をチェック
    [[ ${_BLE_SYNTAX_FEND[ctx]} ]] && "${_BLE_SYNTAX_FEND[ctx]}"
  done

  # 全て記録している筈なので、更新範囲を反映して無くても良い…はず
  # (_ble_syntax_word_umin<0||_ble_syntax_word_umin>_ble_syntax_attr_umin)&&(_ble_syntax_word_umin=_ble_syntax_attr_umin),
  # (_ble_syntax_word_umax<0||_ble_syntax_word_umax<_ble_syntax_attr_uend)&&(_ble_syntax_word_umax=_ble_syntax_attr_uend),

  (((_ble_syntax_attr_umin<0||_ble_syntax_attr_umin>i1)&&(_ble_syntax_attr_umin=i1),
    (_ble_syntax_attr_uend<0||_ble_syntax_attr_uend<i)&&(_ble_syntax_attr_uend=i),
    (i>=i2)?(
      _ble_syntax_dbeg=_ble_syntax_dend=-1
    ):(
      _ble_syntax_dbeg=i,_ble_syntax_dend=i2)))

  # 終端の状態の記録
  if ((i>=iN)); then
    _ble_syntax_stat[iN]="$ctx $((wbegin<0?wbegin:iN-wbegin)) $wtype $((inest<0?inest:iN-inest))"

    # ネスト開始点のエラー表示は +syntax 内で。
    # ここで設定すると部分更新の際に取り消しできないから。
    if ((inest>0)); then
      ((_ble_syntax_attr[iN-1]=ATTR_ERR))
      while ((inest>=0)); do
        ((i=inest))
        ble-syntax/parse/nest-pop
        ((inest>=i&&(inest=i-1)))
      done
    fi
  fi

#%if debug (
  ((${#_ble_syntax_stat[@]}==iN+1)) ||
    ble-stackdump "unexpected array length #arr=${#_ble_syntax_stat[@]} (expected to be $iN), #proto=${#_ble_util_array_prototype[@]} should be >= $iN"
#%)
}

#==============================================================================
#
# syntax-complete
#
#==============================================================================

# ## 関数 ble-syntax/getattr index
# function ble-syntax/getattr {
#   local i
#   attr=
#   for ((i=$1;i>=0;i--)); do
#     if [[ ${_ble_syntax_attr[i]} ]]; then
#       ((attr=_ble_syntax_attr[i]))
#       return
#     fi
#   done
# }

# ## 関数 ble-syntax/getstat index
# function ble-syntax/getstat {
#   local i
#   for ((i=$1;i>=0;i--)); do
#     if [[ ${_ble_syntax_stat[i]} ]]; then
#       stat=(${_ble_syntax_stat[i]})
#       return
#     fi
#   done
# }

function ble-syntax/completion-context/add {
  local source="$1"
  local comp1="$2"
  context[${#context[*]}]="$source $comp1"
}

function ble-syntax/completion-context/check/parameter-expansion {
  local rex_paramx='^\$([a-zA-Z_][a-zA-Z_0-9]*)?$'
  if [[ ${text:i:index-i} =~ $rex_paramx ]]; then
    ble-syntax/completion-context/add variable $((i+1))
  fi
}


## 関数 ble-syntax/completion-context/check-prefix
##   @var[in] text
##   @var[in] index
##   @var[out] context
function ble-syntax/completion-context/check-prefix {
  local rex_param='^[a-zA-Z_][a-zA-Z_0-9]*$'
  local rex_delimiters="^[$_BLE_SYNTAX_CSPACE;|&<>()]"

  local i
  local -a stat=()
  for ((i=index-1;i>=0;i--)); do
    if [[ ${_ble_syntax_stat[i]} ]]; then
      stat=(${_ble_syntax_stat[i]})
      break
    fi
  done

  if [[ ${stat[0]} ]]; then
    local ctx="${stat[0]}" wlen="${stat[1]}"
    local wbegin="$((wlen<0?-1:i-wlen))"
    if ((ctx==CTX_CMDI)); then
      # CTX_CMDI  → コマンドの続き
      ble-syntax/completion-context/add command "$wbegin"
      if [[ ${text:wbegin:index-wbegin} =~ $rex_param ]]; then
        ble-syntax/completion-context/add variable "$wbegin"
      fi
      ble-syntax/completion-context/check/parameter-expansion
    elif ((ctx==CTX_ARGI)); then
      # CTX_ARGI  → 引数の続き
      ble-syntax/completion-context/add file "$wbegin"
      local sub="${text:wbegin:index-wbegin}"
      if [[ $sub == *=* ]]; then
        sub="${sub##*=}"
        ble-syntax/completion-context/add file "$((index-${#sub}))"
      fi
      ble-syntax/completion-context/check/parameter-expansion
    elif ((ctx==CTX_CMDX||
              ctx==CTX_CMDX1||
              ctx==CTX_CMDXV)); then
      # 直前の再開点が CMDX だった場合、
      # 現在地との間にコマンド名があればそれはコマンドである。
      # スペースや ;&| 等のコマンド以外の物がある可能性もある事に注意する。
      local word="${text:i:index-i}"
      if [[ $word =~ $_ble_syntax_rex_simple_word ]]; then
        ble-syntax/completion-context/add command "$i"
        if [[ $word =~ $rex_param ]]; then
          ble-syntax/completion-context/add variable "$i"
        fi
      fi
      ble-syntax/completion-context/check/parameter-expansion
    elif ((ctx==CTX_CMDXF)); then
      # CTX_CMDXF → (( でなければ 変数名
      if [[ ${text:i:index-1} =~ $rex_param ]]; then
        ble-syntax/completion-context/add variable "$i"
      fi
    elif ((ctx==CTX_ARGX)); then
      local sub="${text:i:index-i}"
      if [[ $sub =~ $_ble_syntax_rex_simple_word ]]; then
        ble-syntax/completion-context/add file "$i"
        local rex="^([^'\"\$\\]|\\.)*="
        if [[ $sub =~ $rex ]]; then
          sub="${sub:${#BASH_REMATCH}}"
          ble-syntax/completion-context/add file "$((index-${#sub}))"
        fi
      fi
      ble-syntax/completion-context/check/parameter-expansion
    elif ((ctx==CTX_RDRF||ctx==CTX_VRHS)); then
      # CTX_RDRF: redirect の filename 部分
      # CTX_VRHS: VAR=value の value 部分
      local sub="${text:i:index-i}"
      if [[ $sub =~ $_ble_syntax_rex_simple_word ]]; then
        ble-syntax/completion-context/add file "$i"
      fi
    fi
  fi
}

## 関数 ble-syntax/completion-context/check-here
##   現在地点を開始点とする補完の可能性を列挙します
##   @var[in]  text
##   @var[in]  index
##   @var[out] context
function ble-syntax/completion-context/check-here {
  ((${#context[*]})) && return
  local -a stat
  stat=(${_ble_syntax_stat[index]})
  if [[ ${stat[0]} ]]; then
    # ここで CTX_CMDI や CTX_ARGI は処理しない。
    # 既に check-prefix で引っかかっている筈だから。

    if ((stat[0]==CTX_CMDX||
            stat[0]==CTX_CMDXV||
            stat[0]==CTX_CMDX1)); then
      ble-syntax/completion-context/add command "$index"
      ble-syntax/completion-context/add variable "$index"
    elif ((stat[0]==CTX_CMDXF)); then
      ble-syntax/completion-context/add variable "$index"
    elif ((stat[0]==CTX_ARGX)); then
      ble-syntax/completion-context/add file "$index"
    fi
  fi
}

## 関数 ble-syntax/completion-context
##   @var[out] context[]
function ble-syntax/completion-context {
  local text="$1" index="$2"
  context=()
  ((index<0&&(index=0)))

  ble-syntax/completion-context/check-prefix
  ble-syntax/completion-context/check-here
}

#==============================================================================
#
# syntax-highlight
#
#==============================================================================

# filetype
ATTR_CMD_BOLD=101
ATTR_CMD_BUILTIN=102
ATTR_CMD_ALIAS=103
ATTR_CMD_FUNCTION=104
ATTR_CMD_FILE=105
ATTR_CMD_KEYWORD=106
ATTR_CMD_JOBS=107
ATTR_CMD_DIR=112
ATTR_FILE_DIR=108
ATTR_FILE_LINK=109
ATTR_FILE_EXEC=110
ATTR_FILE_FILE=111

ble-color-defface syntax_default           none
ble-color-defface syntax_command           red
ble-color-defface syntax_quoted            fg=green
ble-color-defface syntax_quotation         fg=green,bold
ble-color-defface syntax_expr              fg=navy
ble-color-defface syntax_error             bg=203,fg=231 # bg=224
ble-color-defface syntax_varname           fg=202
ble-color-defface syntax_delimiter         bold
ble-color-defface syntax_param_expansion   fg=purple
ble-color-defface syntax_history_expansion bg=94,fg=231
ble-color-defface syntax_function_name     fg=purple
ble-color-defface syntax_comment           fg=gray

ble-color-defface command_builtin_dot fg=red,bold
ble-color-defface command_builtin     fg=red
ble-color-defface command_alias       fg=teal
ble-color-defface command_function    fg=purple
ble-color-defface command_file        fg=green
ble-color-defface command_keyword     fg=blue
ble-color-defface command_jobs        fg=red
ble-color-defface command_directory   fg=navy,underline
ble-color-defface filename_directory  fg=navy,underline
ble-color-defface filename_link       fg=teal,underline
ble-color-defface filename_executable fg=green,underline
ble-color-defface filename_other      underline

_ble_syntax_attr2iface=()
function _ble_syntax_attr2iface.define {
  ((_ble_syntax_attr2iface[$1]=_ble_faces__$2))
}
_ble_syntax_attr2iface.define CTX_ARGX     syntax_default
_ble_syntax_attr2iface.define CTX_ARGX0    syntax_default
_ble_syntax_attr2iface.define CTX_CMDX     syntax_default
_ble_syntax_attr2iface.define CTX_CMDXF    syntax_default
_ble_syntax_attr2iface.define CTX_CMDX1    syntax_default
_ble_syntax_attr2iface.define CTX_CMDXV    syntax_default
_ble_syntax_attr2iface.define CTX_ARGI     syntax_default
_ble_syntax_attr2iface.define CTX_CMDI     syntax_command
_ble_syntax_attr2iface.define CTX_VRHS     syntax_default
_ble_syntax_attr2iface.define CTX_QUOT     syntax_quoted
_ble_syntax_attr2iface.define CTX_EXPR     syntax_expr
_ble_syntax_attr2iface.define ATTR_ERR     syntax_error
_ble_syntax_attr2iface.define ATTR_VAR     syntax_varname
_ble_syntax_attr2iface.define ATTR_QDEL    syntax_quotation
_ble_syntax_attr2iface.define ATTR_DEF     syntax_default
_ble_syntax_attr2iface.define ATTR_DEL     syntax_delimiter
_ble_syntax_attr2iface.define CTX_PARAM    syntax_param_expansion
_ble_syntax_attr2iface.define CTX_PWORD    syntax_default
_ble_syntax_attr2iface.define ATTR_HISTX   syntax_history_expansion
_ble_syntax_attr2iface.define ATTR_FUNCDEF syntax_function_name
_ble_syntax_attr2iface.define CTX_VALX     syntax_default
_ble_syntax_attr2iface.define CTX_VALI     syntax_default
_ble_syntax_attr2iface.define ATTR_COMMENT syntax_comment

_ble_syntax_attr2iface.define ATTR_CMD_BOLD     command_builtin_dot
_ble_syntax_attr2iface.define ATTR_CMD_BUILTIN  command_builtin
_ble_syntax_attr2iface.define ATTR_CMD_ALIAS    command_alias
_ble_syntax_attr2iface.define ATTR_CMD_FUNCTION command_function
_ble_syntax_attr2iface.define ATTR_CMD_FILE     command_file
_ble_syntax_attr2iface.define ATTR_CMD_KEYWORD  command_keyword
_ble_syntax_attr2iface.define ATTR_CMD_JOBS     command_jobs
_ble_syntax_attr2iface.define ATTR_CMD_DIR      command_directory
_ble_syntax_attr2iface.define ATTR_FILE_DIR     filename_directory
_ble_syntax_attr2iface.define ATTR_FILE_LINK    filename_link
_ble_syntax_attr2iface.define ATTR_FILE_EXEC    filename_executable
_ble_syntax_attr2iface.define ATTR_FILE_FILE    filename_other

function ble-syntax/attr2g {
  local iface="${_ble_syntax_attr2iface[$1]:-_ble_faces__syntax_default}"
  g="${_ble_faces[iface]}"
}

function ble-syntax/highlight/cmdtype1 {
  type="$1"
  local cmd="$2"
  case "$type:$cmd" in
  (builtin::|builtin:.)
    # 見にくいので太字にする
    ((type=ATTR_CMD_BOLD)) ;;
  (builtin:*)
    ((type=ATTR_CMD_BUILTIN)) ;;
  (alias:*)
    ((type=ATTR_CMD_ALIAS)) ;;
  (function:*)
    ((type=ATTR_CMD_FUNCTION)) ;;
  (file:*)
    ((type=ATTR_CMD_FILE)) ;;
  (keyword:*)
    ((type=ATTR_CMD_KEYWORD)) ;;
  (*:%*)
    # jobs
    if jobs "$cmd" &>/dev/null; then
      ((type=ATTR_CMD_JOBS))
    else
      ((type=ATTR_ERR))
    fi ;;
  (*)
    if [[ -d "$cmd" ]] && shopt -q autocd &>/dev/null; then
      ((type=ATTR_CMD_DIR))
    else
      ((type=ATTR_ERR))
    fi ;;
  esac
}

function ble-syntax/highlight/cmdtype2 {
  local cmd="$1" _0="$2"
  ble-syntax/highlight/cmdtype1 "$(builtin type -t "$cmd" 2>/dev/null)" "$cmd"
  if [[ $type == $ATTR_CMD_ALIAS && "$cmd" != "$_0" ]]; then
    # alias を \ で無効化している場合
    # → unalias して再度 check (2fork)
    type=$(
      unalias "$cmd"
      ble-syntax/highlight/cmdtype1 "$(builtin type -t "$cmd" 2>/dev/null)" "$cmd"
      echo -n "$type")
  elif [[ $type = $ATTR_CMD_KEYWORD && "$cmd" != "$_0" ]]; then
    # keyword (time do if function else elif fi の類) を \ で無効化している場合
    # →file, function, builtin, jobs のどれかになる。以下 3fork+2exec
    if test -z "${cmd##%*}" && jobs "$cmd" &>/dev/null; then
      # %() { :; } として 関数を定義できるが jobs の方が優先される。
      # (% という名の関数を呼び出す方法はない?)
      # でも % で始まる物が keyword になる事はそもそも無いような。
      ((type=ATTR_CMD_JOBS))
    elif ble/util/isfunction "$cmd"; then
      ((type=ATTR_CMD_FUNCTION))
    elif enable -p | fgrep -xq "enable $cmd" &>/dev/null; then
      ((type=ATTR_CMD_BUILTIN))
    elif which "$cmd" &>/dev/null; then
      ((type=ATTR_CMD_FILE))
    else
      ((type=ATTR_ERR))
    fi
  fi
}

if ((_ble_bash>=40000)); then
  declare -A _ble_syntax_highlight_filetype=()
  _ble_syntax_highlight_filetype_version=-1
  ## @var type[out]
  function ble-syntax/highlight/cmdtype {
    local cmd="$1" _0="$2"

    # check cache
    if [[ $_ble_syntax_highlight_filetype_version != $_ble_edit_LINENO ]]; then
      _ble_syntax_highlight_filetype=()
      _ble_syntax_highlight_filetype_version="$_ble_edit_LINENO"
    fi

    type="${_ble_syntax_highlight_filetype[x$_0]}"
    [[ $type ]] && return

    ble-syntax/highlight/cmdtype2 "$cmd" "$_0"
    _ble_syntax_highlight_filetype["x$_0"]="$type"
  }
else
  declare -a _ble_syntax_highlight_filetype=()
  _ble_syntax_highlight_filetype_version=-1
  function ble-syntax/highlight/cmdtype {
    local cmd="$1" _0="$2"

    # check cache
    if [[ $_ble_syntax_highlight_filetype_version != $_ble_edit_LINENO ]]; then
      _ble_syntax_highlight_filetype=()
      _ble_syntax_highlight_filetype_version="$_ble_edit_LINENO"
    fi

    local i iN
    for ((i=0,iN=${#_ble_syntax_highlight_filetype[@]}/2;i<iN;i++)); do
      if [[ ${_ble_syntax_highlight_filetype[2*i]} == x$_0 ]]; then
        type="${_ble_syntax_highlight_filetype[2*i+1]}"
        return
      fi
    done

    ble-syntax/highlight/cmdtype2 "$cmd" "$_0"
    _ble_syntax_highlight_filetype[2*iN]="x$_0"
    _ble_syntax_highlight_filetype[2*iN+1]="$type"
  }
fi

function ble-syntax/highlight/filetype {
  local file="$1" _0="$2"
  [[ ! -e "$file" && ( $file == '~' || $file == '~/'* ) ]] && file="$HOME${file:1}"
  if test -d "$file"; then
    ((type=ATTR_FILE_DIR))
  elif test -h "$file"; then
    ((type=ATTR_FILE_LINK))
  elif test -x "$file"; then
    ((type=ATTR_FILE_EXEC))
  elif test -f "$file"; then
    ((type=ATTR_FILE_FILE))
  else
    type=
  fi
}

# highlighter

function ble-syntax/highlight/set-attribute {
  local i="$1" g="$2"
  if [[ ${_ble_region_highlight_table[i]} != "$g" ]]; then
    ((LAYER_UMIN>i&&(LAYER_UMIN=i),
      LAYER_UMAX<i&&(LAYER_UMAX=i),
      _ble_region_highlight_table[i]=g))
  fi
}

function ble-syntax/highlight/fill-g {
  local g="$1" i
  if [[ $3 ]]; then
    for ((i=$2;i<$3;i++)); do
      ble-syntax/highlight/set-attribute "$i" "$g"
    done
  else
    for ((i=$2;i<iN;i++)); do
      ble-syntax/highlight/set-attribute "$i" "$g"
      [[ ${_ble_syntax_attr[i+1]} ]] && break
    done
  fi
}

_ble_syntax_rex_simple_word=
_ble_syntax_rex_simple_word_element=
function ble-syntax-initialize-rex {
  local quot="'"
  local rex_squot='"[^"]*"|\$"([^"\]|\\.)*"'; rex_squot="${rex_squot//\"/$quot}"
  local rex_dquot='\$?"([^'"${_BLE_SYNTAX_CSPECIAL[CTX_QUOT]}"']|\\.)*"'
  local rex_param='\$([-*@#?$!0_]|[1-9][0-9]*|[a-zA-Z_][a-zA-Z_0-9]*)'
  local rex_param2='\$\{(#?[-*@#?$!0]|[#!]?([1-9][0-9]*|[a-zA-Z_][a-zA-Z_0-9]*))\}' # ${!!} ${!$} はエラーになる。履歴展開の所為?
  local rex_letter='[^'"${_BLE_SYNTAX_CSPECIAL[CTX_ARGI]}"']'
  _ble_syntax_rex_simple_word_element='('"$rex_letter"'|\\.|'"$rex_squot"'|'"$rex_dquot"'|'"$rex_param"'|'"$rex_param2"')'
  _ble_syntax_rex_simple_word='^'"$_ble_syntax_rex_simple_word_element"'+$'
}
ble-syntax-initialize-rex

# adapter に頼らず直接実装したい
function ble-highlight-layer:syntax/touch-range {
  local -i p1="$1" p2="${2:-$1}"
  (((umin<0||umin>p1)&&(umin=p1),
    (umax<0||umax<p2)&&(umax=p2)))
}
function ble-highlight-layer:syntax/fill {
  local _i _arr="$1" _i1="$2" _i2="$3" _v="$4"
  for ((_i=_i1;_i<_i2;_i++)); do
    eval "$_arr[_i]=\"\$_v\""
  done
}

_ble_highlight_layer_syntax_buff=()
_ble_highlight_layer_syntax1_table=()
_ble_highlight_layer_syntax2_table=()
_ble_highlight_layer_syntax3_list=()
_ble_highlight_layer_syntax3_table=() # errors

function ble-highlight-layer:syntax/update-attribute-table {
  ble-highlight-layer/update/shift _ble_highlight_layer_syntax1_table
  if ((_ble_syntax_attr_umin>=0)); then
    ble-highlight-layer:syntax/touch-range _ble_syntax_attr_umin _ble_syntax_attr_umax

    local i g=0
    ((_ble_syntax_attr_umin>0)) &&
      ((g=_ble_highlight_layer_syntax1_table[_ble_syntax_attr_umin-1]))

    for ((i=_ble_syntax_attr_umin;i<_ble_syntax_attr_uend;i++)); do
      if ((${_ble_syntax_attr[i]})); then
        ble-syntax/attr2g "${_ble_syntax_attr[i]}"
      fi
      _ble_highlight_layer_syntax1_table[i]="$g"
    done

    _ble_syntax_attr_umin=-1 _ble_syntax_attr_uend=-1
  fi
}
function ble-highlight-layer:syntax/update-word-table {
  # update table2 (単語の削除に関しては後で考える)
  ble-highlight-layer/update/shift _ble_highlight_layer_syntax2_table
  if ((_ble_syntax_word_umin>=0)); then
    local i g
    local rex_word_data='^[0-9]+[[:space:]]'
    for ((i=_ble_syntax_word_umax;i>=_ble_syntax_word_umin;i--)); do
      if [[ ${_ble_syntax_word[i-1]} =~ $rex_word_data ]]; then
        local -a word
        word=(${_ble_syntax_word[i-1]})
        local wbeg="$((i-word[1]))" wend="$i"
        local wtxt="${text:wbeg:word[1]}"
        local set=
        if [[ $wtxt =~ $_ble_syntax_rex_simple_word ]]; then
          local value type=

          # 単語を展開
          if [[ $wtxt == '['* ]]; then
            # 先頭に [ があると配列添字と解釈されて失敗するので '' を前置する。
            eval "value=(''$wtxt)"
          else
            # 先頭が [ 以外の時は tilde expansion 等が有効になる様に '' は前置しない。
            eval "value=($wtxt)"
          fi

          if ((word[0]==CTX_CMDI)); then
            ble-syntax/highlight/cmdtype "$value" "$wtxt"
          elif ((word[0]==CTX_ARGI||word[0]==CTX_RDRF)); then
            ble-syntax/highlight/filetype "$value" "$wtxt"

            # エラー: ディレクトリにリダイレクトはできない
            ((word[0]==CTX_RDRF&&type==ATTR_FILE_DIR&&(type=ATTR_ERR)))
          elif ((word[0]==ATTR_FUNCDEF)); then
            ((type=ATTR_FUNCDEF))
          fi

          if [[ $type ]]; then
            ble-syntax/attr2g "$type"
            ble-highlight-layer:syntax/fill _ble_highlight_layer_syntax2_table "$wbeg" "$wend" "$g"
            set=1
          fi
        fi

        [[ $set ]] || ble-highlight-layer:syntax/fill _ble_highlight_layer_syntax2_table "$wbeg" "$wend" ''

        ble-highlight-layer:syntax/touch-range "$wbeg" "$wend"
      fi
    done
    _ble_syntax_word_umin=-1 _ble_syntax_word_umax=-1
  fi
}

function ble-highlight-layer:syntax/update-error-table/set {
  local i1="$1" i2="$2" g="$3"
  if ((i1<i2)); then
    ble-highlight-layer:syntax/touch-range "$i1" "$i2"
    ble-highlight-layer:syntax/fill _ble_highlight_layer_syntax3_table "$i1" "$i2" "$g"
    _ble_highlight_layer_syntax3_list[${#_ble_highlight_layer_syntax3_list[@]}]="$i1 $i2"
  fi
}
function ble-highlight-layer:syntax/update-error-table {
  ble-highlight-layer/update/shift _ble_highlight_layer_syntax3_table

  # clear old errors
  #   shift の前の方が簡単に更新できるが、
  #   umin umax を更新する為に shift の後で処理する。
  local j=0 jN="${#_ble_highlight_layer_syntax3_list[*]}"
  if ((jN)); then
    for ((j=0;j<jN;j++)); do
      local -a range
      range=(${_ble_highlight_layer_syntax3_list[j]})

      local a="${range[0]}" b="${range[1]}"
      ((a>=DMAX0?(a+=DMAX-DMAX0):(a>=DMIN&&(a=DMIN)),
        b>=DMAX0?(b+=DMAX-DMAX0):(b>=DMIN&&(b=DMIN))))
      if ((a<b)); then
        ble-highlight-layer:syntax/fill _ble_highlight_layer_syntax3_table "$a" "$b" ''
        ble-highlight-layer:syntax/touch-range "$a" "$b"
      fi
    done
    _ble_highlight_layer_syntax3_list=()
  fi

  # この実装では毎回全てのエラーを設定するので
  # 実は下の様にすれば良いだけ…
  #_ble_highlight_layer_syntax3_table=()

  # set errors
  if [[ ${_ble_syntax_stat[iN]} ]]; then
    local g; ble-color-face2g syntax_error

    # 入れ子が閉じていないエラー
    local -a stat
    stat=(${_ble_syntax_stat[iN]})
    local ctx="${stat[0]}" nlen="${stat[3]}"
    local i inest
    if((nlen>0)); then
      # 終端点の着色
      ble-highlight-layer:syntax/update-error-table/set "$((iN-1))" "$iN" "$g"

      ((inest=iN-nlen))
      while ((inest>=0)); do
        # 開始字句の着色
        local inest2
        for((inest2=inest+1;inest2<iN;inest2++)); do
          [[ ${_ble_syntax_attr[inest2]} ]] && break
        done
        ble-highlight-layer:syntax/update-error-table/set "$inest" "$inest2" "$g"

        ((i=inest))
        ble-syntax/parse/nest-pop
        ((inest>=i&&(inest=i-1)))
      done
    fi

    # コマンド欠落
    if ((ctx==CTX_CMDX1||ctx==CTX_CMDXF)); then
      # 終端点の着色
      ble-highlight-layer:syntax/update-error-table/set "$((iN-1))" "$iN" "$g"
    fi
  fi
}

function ble-highlight-layer:syntax/update {
  local text="$1" player="$2"
  local i iN="${#text}"

  _ble_edit_str.update-syntax

  if [[ $ble_debug ]]; then
    local status
    ble-syntax/print-status -v status
    .ble-line-info.draw "$status"
  fi

  local umin=-1 umax=-1
  # 少なくともこの範囲は文字が変わっているので再描画する必要がある
  ((DMIN>=0)) && umin="$DMIN" umax="$DMAX"

  # .ble-line-info.draw-text "ble-syntax/parse attr_urange = $_ble_syntax_attr_umin-$_ble_syntax_attr_uend, word_urange = $_ble_syntax_word_umin-$_ble_syntax_word_umax"

  ble-highlight-layer:syntax/update-attribute-table
  ble-highlight-layer:syntax/update-word-table
  ble-highlight-layer:syntax/update-error-table

  # shift&sgr 設定
  if ((DMIN>=0)); then
    ble-highlight-layer/update/shift _ble_highlight_layer_syntax_buff
    if ((DMAX>0)); then
      local g sgr ch
      ble-highlight-layer:syntax/getg "$DMAX"
      ble-color-g2sgr -v sgr "$g"
      ch="${_ble_highlight_layer_plain_buff[DMAX]}"
      _ble_highlight_layer_syntax_buff[DMAX]="$sgr$ch"
    fi
  fi

  local i j g gprev=0
  if ((umin>0)); then
    ble-highlight-layer:syntax/getg "$((umin-1))"
    gprev="$g"
  fi

  local sgr
  for ((i=umin;i<umax;i++)); do
    local ch="${_ble_highlight_layer_plain_buff[i]}"
    ble-highlight-layer:syntax/getg "$i"
    [[ $g ]] || ble-highlight-layer/update/getg "$i"
    if ((gprev!=g)); then
      ble-color-g2sgr -v sgr "$g"
      ch="$sgr$ch"
      ((gprev=g))
    fi
    _ble_highlight_layer_syntax_buff[i]="$ch"
  done

  PREV_UMIN="$umin" PREV_UMAX="$umax"
  PREV_BUFF=_ble_highlight_layer_syntax_buff

  # # 以下は単語の分割のデバグ用
  # local -a words=() word
  # for ((i=1;i<=iN;i++)); do
  #   if [[ ${_ble_syntax_word[i-1]} ]]; then
  #     word=(${_ble_syntax_word[i-1]})
  #     local wtxt="${text:i-word[1]:word[1]}" value
  #     if [[ $wtxt =~ $_ble_syntax_rex_simple_word ]]; then
  #       eval "value=$wtxt"
  #     else
  #       value="? ($wtxt)"
  #     fi
  #     ble/util/array-push words "[$value ${word[*]}]"
  #   fi
  # done
  # .ble-line-info.draw-text "${words[*]}"
}

function ble-highlight-layer:syntax/getg {
  local i="$1"
  if [[ ${_ble_highlight_layer_syntax3_table[i]} ]]; then
    g="${_ble_highlight_layer_syntax3_table[i]}"
  elif [[ ${_ble_highlight_layer_syntax2_table[i]} ]]; then
    g="${_ble_highlight_layer_syntax2_table[i]}"
  elif [[ ${_ble_highlight_layer_syntax1_table[i]} ]]; then
    g="${_ble_highlight_layer_syntax1_table[i]}"
  else
    g=
  fi
}

#%#----------------------------------------------------------------------------
#%# test codes
#%#----------------------------------------------------------------------------
#%(

attrg[CTX_ARGX]=$'\e[m'
attrg[CTX_ARGX0]=$'\e[m'
attrg[CTX_CMDX]=$'\e[m'
attrg[CTX_CMDXF]=$'\e[m'
attrg[CTX_CMDX1]=$'\e[m'
attrg[CTX_CMDXV]=$'\e[m'
attrg[CTX_ARGI]=$'\e[m'
attrg[CTX_CMDI]=$'\e[;91m'
attrg[CTX_VRHS]=$'\e[m'
attrg[CTX_RDRD]=$'\e[4m'
attrg[CTX_RDRF]=$'\e[4m'
attrg[CTX_QUOT]=$'\e[;32m'
attrg[CTX_EXPR]=$'\e[;34m'
attrg[ATTR_ERR]=$'\e[;101;97m'
attrg[ATTR_VAR]=$'\e[;38;5;202m'
attrg[ATTR_QDEL]=$'\e[;1;32m'
attrg[ATTR_DEF]=$'\e[m'
attrg[ATTR_DEL]=$'\e[;1m'
attrg[CTX_PARAM]=$'\e[;94m'
attrg[CTX_PWORD]=$'\e[m'

attrg[CTX_VALX]=$'\e[m'
attrg[CTX_VALI]=$'\e[34m'
attrg[ATTR_CMD_KEYWORD]=$'\e[94m'

function mytest/put {
  buff[${#buff[@]}]="$*"
}
function mytest/fflush {
  IFS= eval 'echo -n "${buff[*]}"'
  buff=()
}
function mytest {
  local text="$1"
  ble-syntax/parse "$text"

  # # update test
  # ble-syntax/parse "$text" 15 16

  # # insertion test
  # text="${text::5}""hello; echo""${text:5}"
  # ble-syntax/parse "$text" 5 16 5
  # echo update $_ble_syntax_attr_umin-$_ble_syntax_attr_uend

  # # delete test
  # text="${text::5}""${text:10}"
  # ble-syntax/parse "$text" 5 5 10
  # echo update $_ble_syntax_attr_umin-$_ble_syntax_attr_uend

  local -a buff=()

  # echo "$text"
  local ctxg=$'\e[m'
  for ((i=0;i<${#text};i++)); do
    if ((${_ble_syntax_attr[i]})); then
      ctxg="${attrg[_ble_syntax_attr[i]]:-[40;97m}"
    fi
    mytest/put "$ctxg${text:i:1}"
  done
  mytest/put $'\e[m\n'

  for ((i=0;i<${#text};i++)); do
    if ((${_ble_syntax_stat[i]%% *})); then
      mytest/put '>'
    else
      mytest/put ' '
    fi
    # local ret
    # .ble-text.s2c "$text" "$i"
    # .ble-text.c2w "$ret"
  done
  mytest/put $'\n'
  mytest/fflush

  # local ctxc=' '
  # for ((i=0;i<${#text};i++)); do
  #   if ((${_ble_syntax_attr[i]})); then
  #     ctxc="${attrc[_ble_syntax_attr[i]]:-'?'}"
  #   fi
  #   mytest/put "$ctxc"
  # done
  # mytest/put $'\n'
}
# mytest 'echo hello world'
# mytest 'echo "hello world"'
# mytest 'echo a"hed"a "aa"b b"aa" aa'

mytest 'echo a"$"a a"\$\",$*,$var,$12"a $*,$var,$12'
mytest 'echo a"---$((1+a[12]*3))---$(echo hello)---"a'
mytest 'a=1 b[x[y]]=1234 echo <( world ) > hello; ( sub shell); ((1+2*3));'
mytest 'a=${#hello} b=${world[10]:1:(5+2)*3} c=${arr[*]%%"test"$(cmd).cpp} d+=12'
mytest 'for ((i=0;i<10;i++)); do echo hello; done; { : '"'worlds'\\'' record'"'; }'
mytest '[[ echo == echo ]]; echo hello'

# ble-syntax/parse "echo hello"
# for ((i=0;i<${#_ble_syntax_stat[@]};i++)); do
#   if [[ ${_ble_syntax_stat[i]} ]]; then
#     echo "$i ${_ble_syntax_stat[i]}"
#   fi
# done

# 関数名に使える文字?
#
# 全く使えない文字 |&;<>()!$\'"`
#
# name() の形式だと
#   { } をコマンドとして定義できない。function の形式なら可能
#
# set -H だと
#   ! を履歴展開の構文で含む関数は定義できない。
#   set +H にしておけば定義する事ができる。
#   name() の形式では ^ で始まる関数は定義できない。
#
# extglob on だと
#   ? * @ + ! は name() の形式で定義できない。
#   一応 name () と間に空白を挟めば定義できる。
#   function ?() *() などとすると "?()" という名前で関数が作られる。
#

#%)
#%#----------------------------------------------------------------------------
#%)
#%m main main.r/\<ATTR_/BLE_ATTR_/
#%m main main.r/\<CTX_/BLE_CTX_/
#%x main
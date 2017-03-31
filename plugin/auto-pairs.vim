let g:AutoPairs = {'(':')', '[':']', '{':'}',"'":"'",'"':'"', '`':'`'}

let g:AutoPairsParens = {'(':')', '[':']', '{':'}'}

let s:Go = "\<C-G>U"

let s:Left = s:Go."\<LEFT>"
let s:Right = s:Go."\<RIGHT>"

" Will auto generated {']' => '[', ..., '}' => '{'}in initialize.
let g:AutoPairsClosedPairs = {}


function! AutoPairsInsert(key)

  let line = getline('.')
  let pos = col('.') - 1
  let before = strpart(line, 0, pos)
  let after = strpart(line, pos)
  let next_chars = split(after, '\zs')
  let current_char = get(next_chars, 0, '')
  let next_char = get(next_chars, 1, '')
  let prev_chars = split(before, '\zs')
  let prev_char = get(prev_chars, -1, '')

  let eol = 0
  if col('$') -  col('.') <= 1
    let eol = 1
  end

  " Ignore auto close if prev character is \
  if prev_char == '\'
    return a:key
  end

  " The key is difference open-pair, then it means only for ) ] } by default
  if !has_key(b:AutoPairs, a:key)
    let b:autopairs_saved_pair = [a:key, getpos('.')]

    " Skip the character if current character is the same as input
    if current_char == a:key
      return s:Right
    end

      " Skip the character if next character is space
    if current_char == ' ' && next_char == a:key
      return s:Right.s:Right
    end

    " Skip the character if closed pair is next character
    if current_char == ''
      let next_lineno = line('.')+1
      let next_line = getline(nextnonblank(next_lineno))
      let next_char = matchstr(next_line, '\s*\zs.')
      if next_char == a:key
        return "\<ESC>e^a"
      endif
    endif

    " Insert directly if the key is not an open key
    return a:key
  end

  let open = a:key
  let close = b:AutoPairs[open]

  if current_char == close && open == close
    return s:Right
  end

  " Ignore auto close ' if follows a word
  " MUST after closed check. 'hello|'
  if a:key == "'" && prev_char =~ '\v\w'
    return a:key
  end

  " TODO
  " 字符前输入不匹配
  if current_char =~'\v\w' || current_char == "'" || current_char == '"'
    return a:key
  end

  " support for ''' ``` and """
  if open == close
    " The key must be ' " `
    let pprev_char = line[col('.')-3]
    if pprev_char == open && prev_char == open
      " Double pair found
      return repeat(a:key, 4) . repeat(s:Left, 3)
    end
  end

  let quotes_num = 0
  " Ignore comment line for vim file
  if &filetype == 'vim' && a:key == '"'
    if before =~ '^\s*$'
      return a:key
    end
    if before =~ '^\s*"'
      let quotes_num = -1
    end
  end

  " Keep quote number is odd.
  " Because quotes should be matched in the same line in most of situation
  if open == close
    " Remove \\ \" \'
    let cleaned_line = substitute(line, '\v(\\.)', '', 'g')
    let n = quotes_num
    let pos = 0
    while 1
      let pos = stridx(cleaned_line, open, pos)
      if pos == -1
        break
      end
      let n = n + 1
      let pos = pos + 1
    endwhile
    if n % 2 == 1
      return a:key
    endif
  endif

  return open.close.s:Left
endfunction

function! AutoPairsDelete()

  let line = getline('.')
  let pos = col('.') - 1
  let current_char = get(split(strpart(line, pos), '\zs'), 0, '')
  let prev_chars = split(strpart(line, 0, pos), '\zs')
  let prev_char = get(prev_chars, -1, '')
  let pprev_char = get(prev_chars, -2, '')

  if pprev_char == '\'
    return "\<BS>"
  end

  " Delete last two spaces in parens, work with MapSpace
  if has_key(b:AutoPairs, pprev_char) && prev_char == ' ' && current_char == ' '
    return "\<BS>\<DEL>"
  endif

  " Delete Repeated Pair eg: '''|''' [[|]] {{|}}
  if has_key(b:AutoPairs, prev_char)
    let times = 0
    let p = -1
    while get(prev_chars, p, '') == prev_char
      let p = p - 1
      let times = times + 1
    endwhile

    let close = b:AutoPairs[prev_char]
    let left = repeat(prev_char, times)
    let right = repeat(close, times)

    let before = strpart(line, pos-times, times)
    let after  = strpart(line, pos, times)
    if left == before && right == after
      return repeat("\<BS>\<DEL>", times)
    end
  end


  if has_key(b:AutoPairs, prev_char)
    let close = b:AutoPairs[prev_char]
    if match(line,'^\s*'.close, col('.')-1) != -1
      " Delete (|___)
      let space = matchstr(line, '^\s*', col('.')-1)
      return "\<BS>". repeat("\<DEL>", len(space)+1)
    elseif match(line, '^\s*$', col('.')-1) != -1
      " Delete (|__\n___)
      let nline = getline(line('.')+1)
      if nline =~ '^\s*'.close
        if &filetype == 'vim' && prev_char == '"'
          " Keep next line's comment
          return "\<BS>"
        end

        let space = matchstr(nline, '^\s*')
        return "\<BS>\<DEL>". repeat("\<DEL>", len(space)+1)
      end
    end
  end

  return "\<BS>"
endfunction


function! AutoPairsMap(key)
  " | is special key which separate map command from text
  let key = a:key
  if key == '|'
    let key = '<BAR>'
  end
  let escaped_key = substitute(key, "'", "''", 'g')
  " use expr will cause search() doesn't work
  execute 'inoremap <buffer> <silent> '.key." <C-R>=AutoPairsInsert('".escaped_key."')<CR>"
endfunction


function! AutoPairsReturn()

  let line = getline('.')
  let pline = getline(line('.')-1)
  let prev_char = pline[strlen(pline)-1]
  let cmd = ''
  let cur_char = line[col('.')-1]
  if has_key(b:AutoPairs, prev_char) && b:AutoPairs[prev_char] == cur_char
    if winline() * 3 >= winheight(0) * 2
      " Recenter before adding new line to avoid replacing line content
      let cmd = "zz"
    end

    " If equalprg has been set, then avoid call =
    " https://github.com/jiangmiao/auto-pairs/issues/24
    if &equalprg != ''
      return "\<ESC>".cmd."O"
    endif

    " conflict with javascript and coffee
    " javascript   need   indent new line
    " coffeescript forbid indent new line
    if &filetype == 'coffeescript' || &filetype == 'coffee'
      return "\<ESC>".cmd."k==o"
    else
      return "\<ESC>".cmd."=ko"
    endif
  end
  return ''
endfunction

function! AutoPairsSpace()
  let line = getline('.')
  let prev_char = line[col('.')-2]
  let cmd = ''
  let cur_char =line[col('.')-1]
  if has_key(g:AutoPairsParens, prev_char) && g:AutoPairsParens[prev_char] == cur_char
    let cmd = "\<SPACE>".s:Left
  endif
  return "\<SPACE>".cmd
endfunction


function! AutoPairsInit()
  let b:autopairs_loaded  = 1
  let b:AutoPairsClosedPairs = {}

  if !exists('b:AutoPairs')
    let b:AutoPairs = g:AutoPairs
  end

  " buffer level map pairs keys
  for [open, close] in items(b:AutoPairs)
    call AutoPairsMap(open)
    if open != close
      call AutoPairsMap(close)
    end
    let b:AutoPairsClosedPairs[close] = open
  endfor

  " Still use <buffer> level mapping for <BS> <SPACE>
  " Use <C-R> instead of <expr> for issue #14 sometimes press BS output strange words
  execute 'inoremap <buffer> <silent> <BS> <C-R>=AutoPairsDelete()<CR>'

  " Try to respect abbreviations on a <SPACE>
  let do_abbrev = ""
  let do_abbrev = "<C-]>"
  execute 'inoremap <buffer> <silent> <SPACE> '.do_abbrev.'<C-R>=AutoPairsSpace()<CR>'
endfunction


function! AutoPairsTryInit()
  if exists('b:autopairs_loaded')
    return
  end

  let old_cr = '<CR>'
  let is_expr = 0

  if old_cr !~ 'AutoPairsReturn'
    if is_expr
      " remap <expr> to `name` to avoid mix expr and non-expr mode
      execute 'inoremap <buffer> <expr> <script> '. wrapper_name . ' ' . old_cr
      let old_cr = wrapper_name
    end
    " Always silent mapping
    execute 'inoremap <script> <buffer> <silent> <CR> '.old_cr.'<SID>AutoPairsReturn'
  end
  call AutoPairsInit()
endfunction

" Always silent the command
inoremap <silent> <SID>AutoPairsReturn <C-R>=AutoPairsReturn()<CR>
imap <script> <Plug>AutoPairsReturn <SID>AutoPairsReturn


au BufEnter * :call AutoPairsTryInit()

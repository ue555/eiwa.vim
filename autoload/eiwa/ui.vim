vim9script

# Window and buffer management for the eiwa.vim interface.
#
# The "float" layout shows the history in a popup window and the input area
# in a bottom split, because Vim popup windows cannot be edited.

import autoload 'eiwa/render.vim'

var history_buf = -1
var input_buf = -1
var history_win = -1
var input_win = -1
var origin_win = -1
var options: dict<any> = {}
var handlers: dict<func> = {}
var is_float = false
var closing = false
var margin_windows: list<number> = []
var margin_buffers: list<number> = []
var input_frame: list<number> = []
var restore_sizes = ''
var paste_burst = false
var paste_timer = -1

const border_chars = {
  rounded: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
  single: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
  double: ['═', '║', '═', '║', '╔', '╗', '╝', '╚'],
  solid: [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
}

def ValidWindow(win: number): bool
  return win > 0 && win_gettype(win) != 'unknown'
enddef

def ValidBuffer(buf: number): bool
  return buf > 0 && bufexists(buf)
enddef

def NewBuffer(filetype: string, modifiable: bool): number
  var buf = bufadd('')
  noautocmd call bufload(buf)
  setbufvar(buf, '&buftype', 'nofile')
  setbufvar(buf, '&bufhidden', 'wipe')
  setbufvar(buf, '&swapfile', 0)
  setbufvar(buf, '&buflisted', 0)
  setbufvar(buf, '&modifiable', modifiable ? 1 : 0)
  setbufvar(buf, '&filetype', filetype)
  setbufvar(buf, '&autoindent', 0)
  setbufvar(buf, '&smartindent', 0)
  setbufvar(buf, '&indentexpr', '')
  return buf
enddef

def SetWindowOptions(win: number)
  setwinvar(win, '&number', 0)
  setwinvar(win, '&relativenumber', 0)
  setwinvar(win, '&signcolumn', 'no')
  setwinvar(win, '&foldcolumn', 0)
  setwinvar(win, '&wrap', 1)
  setwinvar(win, '&cursorline', 0)
  setwinvar(win, '&list', 0)
  setwinvar(win, '&scrolloff', 0)
  setwinvar(win, '&wincolor', 'EiwaNormal')
enddef

def HasBorder(): bool
  return options.window.border != 'none'
enddef

def HistoryTitle(width: number): string
  var fill = HasBorder() ? get(border_chars, options.window.border, border_chars.single)[0] : ' '
  return repeat(fill, max([0, (width - 6) / 2])) .. ' Eiwa '
enddef

def FloatGeometry(): dict<number>
  var columns = &columns
  var tabline = (&showtabline == 2 || (&showtabline == 1 && tabpagenr('$') > 1)) ? 1 : 0
  var input_rows = options.window.input_height + 1
  var region = max([8, &lines - &cmdheight - tabline - input_rows])
  var frame = HasBorder() ? 2 : 0
  var outer_width = max([30, min([columns - 2, float2nr(floor(columns * options.window.width))])])
  var outer_height = max([5, min([region - 1, float2nr(floor(region * options.window.height))])])
  var row = tabline + max([0, (region - outer_height) / 2]) + 1
  var col = max([0, (columns - outer_width) / 2]) + 1
  if ValidWindow(input_win)
    col = max([1, win_screenpos(input_win)[1] - (HasBorder() ? 1 : 0)])
    outer_width = winwidth(input_win) + frame
    # Keep the two panels together, with one row between their borders.
    var bottom = win_screenpos(input_win)[0] - (HasBorder() ? 2 : 1)
    outer_height = min([outer_height, bottom - tabline - 1])
    row = max([tabline + 1, bottom - outer_height])
  endif
  return {
    line: row,
    col: col,
    width: outer_width - frame,
    height: max([1, outer_height - frame]),
  }
enddef

def PopupOptions(geometry: dict<number>): dict<any>
  var popup: dict<any> = {
    pos: 'topleft',
    line: geometry.line,
    col: geometry.col,
    minwidth: geometry.width,
    maxwidth: geometry.width,
    minheight: geometry.height,
    maxheight: geometry.height,
    title: HistoryTitle(geometry.width),
    wrap: 1,
    scrollbar: 1,
    mapping: 0,
    drag: 0,
    resize: 0,
    fixed: 1,
    firstline: 0,
    highlight: 'EiwaNormal',
    zindex: 50,
  }
  if HasBorder()
    popup.border = [1, 1, 1, 1]
    popup.borderchars = get(border_chars, options.window.border, border_chars.single)
    popup.borderhighlight = ['EiwaBorder']
  endif
  return popup
enddef

def OpenInputSplit(modifier: string)
  execute 'noautocmd ' .. modifier .. ' :' .. options.window.input_height .. 'split'
  input_win = win_getid()
  execute 'noautocmd buffer ' .. input_buf
  setlocal winfixheight
  &l:statusline = ' Input (' .. options.keymaps.submit .. ': translate | Ctrl-J: newline | Esc: close)'
enddef

def CenterInput()
  var width = max([30, min([&columns - 4, float2nr(floor(&columns * options.window.width)) - 2])])
  var margin = (&columns - width - 2) / 2
  if margin < &winminwidth + 1
    return
  endif
  for side in ['leftabove', 'rightbelow']
    win_gotoid(input_win)
    execute 'noautocmd ' .. side .. ' vertical :' .. margin .. 'split'
    var win = win_getid()
    var buf = NewBuffer('eiwa-margin', false)
    execute 'noautocmd buffer ' .. buf
    SetWindowOptions(win)
    setlocal winfixwidth
    setlocal statusline=\ 
    setlocal fillchars=eob:\ 
    margin_windows->add(win)
    margin_buffers->add(buf)
  endfor
  win_gotoid(input_win)
  execute 'vertical resize ' .. width
  &l:statusline = ' Input | ' .. options.keymaps.submit .. ': translate | Ctrl-J: newline | Ctrl-V: paste | Esc: close'
enddef

# Thin popup strips frame the editable split without covering its text/cursor.
def DrawInputFrame()
  for win in input_frame
    if ValidWindow(win)
      popup_close(win)
    endif
  endfor
  input_frame = []
  if !HasBorder() || len(margin_windows) != 2
    return
  endif
  var [row, col] = win_screenpos(input_win)
  var width = winwidth(input_win)
  var height = winheight(input_win)
  var chars = get(border_chars, options.window.border, border_chars.single)
  var title = ' Input | ' .. options.keymaps.submit .. ': translate | Ctrl-J: newline '
  title = strcharpart(title, 0, max([0, width]))
  var top = chars[4] .. title .. repeat(chars[0], max([0, width - strdisplaywidth(title)])) .. chars[5]
  var bottom = chars[7] .. repeat(chars[2], width) .. chars[6]
  # Cover statusline decorations from the editor and statusline plugins.
  var left_padding = repeat(' ', max([0, col - 2]))
  var right_padding = repeat(' ', max([0, &columns - col - width]))
  var strips = [
    {line: row - 1, col: 1, text: [left_padding .. top .. right_padding]},
    {line: row + height, col: 1, text: [left_padding .. bottom .. right_padding]},
    {line: row, col: col - 1, text: repeat([chars[3]], height)},
    {line: row, col: col + width, text: repeat([chars[1]], height)},
  ]
  for strip in strips
    input_frame->add(popup_create(strip.text, {
      line: strip.line, col: strip.col, pos: 'topleft',
      highlight: 'EiwaBorder', wrap: 0, scrollbar: 0,
      mapping: 0, zindex: 51, fixed: 1,
    }))
  endfor
enddef

def ResizeInput()
  if len(margin_windows) != 2
    return
  endif
  var width = max([1, min([&columns - 4, float2nr(floor(&columns * options.window.width)) - 2])])
  var margin = max([&winminwidth, (&columns - width - 2) / 2])
  for win in margin_windows
    if ValidWindow(win)
      win_execute(win, 'noautocmd vertical resize ' .. margin)
    endif
  endfor
  win_execute(input_win, 'noautocmd vertical resize ' .. width)
enddef

def FloatLayout()
  OpenInputSplit('botright')
  CenterInput()
  history_win = popup_create(history_buf, PopupOptions(FloatGeometry()))
  DrawInputFrame()
enddef

def SplitLayout(position: string)
  var temporary_buf = -1
  if position == 'right'
    botright vsplit
    history_win = win_getid()
    execute 'vertical resize ' .. max([30, float2nr(floor(&columns * options.window.split_width))])
  elseif position == 'bottom'
    botright new
    history_win = win_getid()
    temporary_buf = bufnr()
    execute 'resize ' .. max([6, float2nr(floor(&lines * options.window.split_height))])
  else
    tabnew
    t:eiwa_tab = 1
    history_win = win_getid()
    temporary_buf = bufnr()
  endif
  execute 'buffer ' .. history_buf
  if temporary_buf > 0 && temporary_buf != history_buf && bufexists(temporary_buf)
      && bufname(temporary_buf) == '' && !getbufvar(temporary_buf, '&modified')
    execute 'silent! bwipeout! ' .. temporary_buf
  endif
  OpenInputSplit('belowright')
enddef

def PageSize(): number
  if !ValidWindow(history_win)
    return 1
  endif
  var height = is_float ? get(popup_getpos(history_win), 'core_height', 3) : winheight(history_win)
  return max([1, height - 2])
enddef

# Number of screen rows a buffer line occupies in the popup with 'wrap' set.
def DisplayRows(text: string, width: number): number
  var cells = max([1, strdisplaywidth(text)])
  return (cells + width - 1) / width
enddef

# First buffer line that keeps the end of the history visible in the popup.
def PopupBottomFirstline(): number
  var pos = popup_getpos(history_win)
  var width = max([1, get(pos, 'core_width', 1)])
  var height = max([1, get(pos, 'core_height', 1)])
  var last = line('$', history_win)
  var rows = 0
  var first = last
  while first >= 1
    rows += DisplayRows(getbufline(history_buf, first)[0], width)
    if rows >= height
      break
    endif
    first -= 1
  endwhile
  return max([1, first])
enddef

def ScrollToBottom()
  if !ValidWindow(history_win)
    return
  endif
  if is_float
    popup_setoptions(history_win, {firstline: PopupBottomFirstline()})
  else
    win_execute(history_win, 'normal! G')
  endif
enddef

def ScrollHistory(amount: number)
  if !ValidWindow(history_win) || amount == 0
    return
  endif
  if is_float
    var current = get(popup_getpos(history_win), 'firstline', 1)
    var target = max([1, min([line('$', history_win), current + amount])])
    popup_setoptions(history_win, {firstline: target})
  elseif amount > 0
    win_execute(history_win, 'normal! ' .. amount .. "\<C-e>")
  else
    win_execute(history_win, 'normal! ' .. (-amount) .. "\<C-y>")
  endif
enddef

def FocusInput()
  if ValidWindow(input_win)
    win_gotoid(input_win)
    startinsert
  endif
enddef

def OnSubmit()
  handlers.submit()
enddef

def EndPasteBurst(timer: number)
  paste_burst = false
  paste_timer = -1
enddef

# Bracketed/clipboard paste bypasses mappings. For terminals that send a stream
# of ordinary keys, retain Enter while more input is queued, including a final
# newline in the same burst. A separate Enter after the burst submits the draft.
def EnterKey(): string
  var next = getchar(1)
  if paste_burst || (next != 0 && next != 27 && next != 28)
    paste_burst = true
    if paste_timer != -1
      timer_stop(paste_timer)
    endif
    paste_timer = timer_start(150, EndPasteBurst)
    return "\<CR>"
  endif
  return "\<ScriptCmd>OnSubmit()\<CR>"
enddef

def OnCancel()
  handlers.cancel()
enddef

def OnClose()
  handlers.close()
enddef

# Insert clipboard text as buffer lines, preserving newlines and indentation.
export def PasteText(text: string)
  if !ValidBuffer(input_buf) || text == ''
    return
  endif
  var normalized = substitute(text, "\r\n", "\n", 'g')
  normalized = substitute(normalized, "\r", "\n", 'g')
  var pasted = split(normalized, "\n", 1)
  var row = line('.')
  var column = col('.') - 1
  var current = getbufline(input_buf, row)[0]
  pasted[0] = strpart(current, 0, column) .. pasted[0]
  var last_column = strlen(pasted[-1]) + 1
  pasted[-1] ..= strpart(current, column)
  setbufline(input_buf, row, pasted[0])
  if len(pasted) > 1
    appendbufline(input_buf, row, pasted[1 :])
  endif
  cursor(row + len(pasted) - 1, last_column)
enddef

def PasteClipboard()
  if !ValidWindow(input_win)
    return
  endif
  noautocmd call win_gotoid(input_win)
  if has('clipboard')
    PasteText(getreg('+'))
  else
    PasteText(getreg('"'))
  endif
enddef

def SetMappings()
  var keymaps = options.keymaps
  # The input window is current when this runs.
  # Preserve an ordinary newline when another submit key is configured.
  inoremap <buffer> <CR> <CR>
  for mode in ['n', 'i']
    execute $'{mode}noremap <buffer><silent><nowait> {keymaps.submit} <ScriptCmd>OnSubmit()<CR>'
    execute $'{mode}noremap <buffer><silent><nowait> {keymaps.cancel} <ScriptCmd>OnCancel()<CR>'
    execute $'{mode}noremap <buffer><silent><nowait> <Esc> <ScriptCmd>OnClose()<CR>'
    execute $'{mode}noremap <buffer><silent><nowait> <PageUp> <ScriptCmd>ScrollHistory(-PageSize())<CR>'
    execute $'{mode}noremap <buffer><silent><nowait> <PageDown> <ScriptCmd>ScrollHistory(PageSize())<CR>'
  endfor
  if index(['<cr>', '<enter>', '<return>'], tolower(keymaps.submit)) >= 0
    inoremap <buffer><silent><expr> <CR> EnterKey()
  endif
  execute $'nnoremap <buffer><silent><nowait> {keymaps.close} <ScriptCmd>OnClose()<CR>'
  inoremap <buffer><silent> <C-v> <ScriptCmd>PasteClipboard()<CR>
  inoremap <buffer><silent> <C-S-v> <ScriptCmd>PasteClipboard()<CR>
  nnoremap <buffer><silent> <C-S-v> <ScriptCmd>PasteClipboard()<CR>
  nnoremap <buffer><silent> <C-v> <ScriptCmd>PasteClipboard()<CR>
  inoremap <buffer><silent> <S-Insert> <ScriptCmd>PasteClipboard()<CR>
  nnoremap <buffer><silent> <S-Insert> <ScriptCmd>PasteClipboard()<CR>
  inoremap <buffer> <S-CR> <CR>
  inoremap <buffer> <C-j> <CR>

  if !is_float && ValidWindow(history_win)
    var commands = [
      $'nnoremap <buffer><silent><nowait> {keymaps.close} <ScriptCmd>OnClose()<CR>',
      'nnoremap <buffer><silent><nowait> <Esc> <ScriptCmd>OnClose()<CR>',
      $'nnoremap <buffer><silent><nowait> {keymaps.cancel} <ScriptCmd>OnCancel()<CR>',
      'nnoremap <buffer><silent><nowait> i <ScriptCmd>FocusInput()<CR>',
    ]
    win_execute(history_win, commands)
  endif
enddef

def FindPluginTab(): number
  for tab in range(1, tabpagenr('$'))
    if gettabvar(tab, 'eiwa_tab', 0)
      return tab
    endif
  endfor
  return 0
enddef

def DismissWindow(win: number)
  if !ValidWindow(win)
    return
  endif
  if win_gettype(win) == 'popup'
    popup_close(win)
    return
  endif
  var [tab, _] = win_id2tabwin(win)
  win_gotoid(win)
  if tabpagewinnr(tab, '$') > 1
    noautocmd close!
  else
    enew!
  endif
enddef

export def OnInputWiped()
  if closing
    return
  endif
  timer_start(0, (_) => Close())
enddef

export def Open(config: dict<any>, callbacks: dict<func>)
  if IsOpen()
    FocusInput()
    return
  endif
  if ValidWindow(history_win) || ValidWindow(input_win)
    Close()
  endif

  options = config
  handlers = callbacks
  origin_win = win_getid()
  restore_sizes = winrestcmd()
  history_buf = NewBuffer('eiwa-history', false)
  input_buf = NewBuffer('eiwa-input', true)
  is_float = options.window.position == 'float'

  if is_float
    FloatLayout()
  else
    SplitLayout(options.window.position)
  endif

  SetWindowOptions(history_win)
  SetWindowOptions(input_win)
  SetMappings()
  augroup EiwaUI
    autocmd!
    execute $'autocmd BufWipeout <buffer={input_buf}> ++once call eiwa#ui#OnInputWiped()'
  augroup END
  callbacks.render()
  FocusInput()
enddef

export def Close()
  if closing
    return
  endif
  closing = true
  if paste_timer != -1
    timer_stop(paste_timer)
  endif
  paste_timer = -1
  paste_burst = false
  try
    augroup EiwaUI
      autocmd!
    augroup END
    for win in input_frame
      DismissWindow(win)
    endfor
    var tab = FindPluginTab()
    if tab > 0 && tabpagenr('$') > 1
      execute 'tabclose! ' .. tab
    else
      DismissWindow(input_win)
      DismissWindow(history_win)
    endif
    for win in margin_windows
      DismissWindow(win)
    endfor
    for buf in [history_buf, input_buf] + margin_buffers
      if ValidBuffer(buf)
        execute 'silent! bwipeout! ' .. buf
      endif
    endfor
  finally
    history_win = -1
    input_win = -1
    history_buf = -1
    input_buf = -1
    margin_windows = []
    margin_buffers = []
    input_frame = []
    closing = false
  endtry
  if ValidWindow(origin_win)
    win_gotoid(origin_win)
    execute 'silent! ' .. restore_sizes
  endif
  origin_win = -1
enddef

export def IsOpen(): bool
  return ValidWindow(history_win) && ValidWindow(input_win)
enddef

export def Input(): string
  if !ValidBuffer(input_buf)
    return ''
  endif
  return join(getbufline(input_buf, 1, '$'), "\n")
enddef

export def ClearInput()
  if ValidBuffer(input_buf)
    silent! deletebufline(input_buf, 1, '$')
  endif
enddef

export def Render(messages: list<dict<any>>, status: string)
  render.Render(history_buf, messages, status)
  ScrollToBottom()
enddef

export def Resize()
  if !IsOpen() || !is_float
    return
  endif
  ResizeInput()
  var geometry = FloatGeometry()
  popup_move(history_win, {
    line: geometry.line,
    col: geometry.col,
    minwidth: geometry.width,
    maxwidth: geometry.width,
    minheight: geometry.height,
    maxheight: geometry.height,
  })
  popup_setoptions(history_win, {title: HistoryTitle(geometry.width)})
  DrawInputFrame()
  ScrollToBottom()
enddef

export def HistoryWindow(): number
  return history_win
enddef

export def InputWindow(): number
  return input_win
enddef

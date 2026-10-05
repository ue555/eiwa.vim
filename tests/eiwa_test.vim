vim9script

import autoload 'eiwa.vim'
import autoload 'eiwa/session.vim'
import autoload 'eiwa/process.vim'
import autoload 'eiwa/ui.vim'

def AssertEqual(expected: any, actual: any, message = 'values differ')
  if expected != actual
    throw message .. "\nexpected: " .. string(expected) .. "\nactual: " .. string(actual)
  endif
enddef

def WindowsWithFiletype(filetype: string): list<number>
  var windows: list<number> = []
  for info in getwininfo()
    if getbufvar(info.bufnr, '&filetype') == filetype
      windows->add(info.winid)
    endif
  endfor
  for popup in popup_list()
    if getbufvar(winbufnr(popup), '&filetype') == filetype
      windows->add(popup)
    endif
  endfor
  return windows
enddef

def ListedBuffers(): number
  return len(filter(range(1, bufnr('$')), (_, buf) => bufexists(buf) && buflisted(buf)))
enddef

def WaitFor(Condition: func(): bool, timeout: number): bool
  var waited = 0
  while waited < timeout
    if Condition()
      return true
    endif
    sleep 10m
    waited += 10
  endwhile
  return Condition()
enddef

AssertEqual(2, exists(':Eiwa'))
AssertEqual(2, exists(':EiwaSubmit'))
AssertEqual(2, exists(':EiwaClose'))
AssertEqual(2, exists(':EiwaClear'))
AssertEqual(2, exists(':EiwaCancel'))
AssertEqual(2, exists(':EiwaNewSession'))

session.Clear()
session.Configure({max_messages: 2})
session.Add('user', 'one', '1')
session.Add('assistant', 'two', '1')
session.Add('user', 'three', '2')
AssertEqual(2, len(session.GetMessages()), 'session must enforce its history limit')
session.AppendAssistant('2', 'four')
AssertEqual('four', session.GetMessages()[-1].content, 'append must create an assistant message')
session.Clear()

var agent = getcwd() .. '/bin/eiwa-agent' .. (has('win32') ? '.exe' : '')
AssertEqual(1, executable(agent), 'agent binary must exist: ' .. agent)
AssertEqual(['x', 'serve'], process.ResolveCommand('x'), 'string command must receive serve')
AssertEqual(['a', 'b'], process.ResolveCommand(['a', 'b']), 'list command must be used verbatim')

var invalid_height = true
try
  eiwa.Setup({window: {input_height: 1.5}})
  invalid_height = false
catch
endtry
AssertEqual(true, invalid_height, 'fractional input heights must be rejected')

var invalid_style = true
try
  eiwa.Setup({api: {style: 'casual'}})
  invalid_style = false
catch
endtry
AssertEqual(true, invalid_style, 'unknown styles must be rejected')

var initial_listed = ListedBuffers()
var initial_windows = winnr('$')
var initial_popups = len(popup_list())
for position in ['float', 'right', 'bottom', 'tab']
  eiwa.Setup({
    command: [agent, 'serve', '--provider', 'placeholder'],
    window: {position: position},
  })
  eiwa.Open()
  AssertEqual(true, ui.IsOpen(), position .. ' layout must open')
  AssertEqual(1, len(WindowsWithFiletype('eiwa-history')), position .. ' layout must show one history window')
  AssertEqual(1, len(WindowsWithFiletype('eiwa-input')), position .. ' layout must show one input window')
  eiwa.Close()
  AssertEqual(false, ui.IsOpen(), position .. ' layout must close')
  AssertEqual(0, len(WindowsWithFiletype('eiwa-history')), position .. ' layout must remove the history window')
  AssertEqual(initial_listed, ListedBuffers(), position .. ' layout must not leak listed buffers')
  AssertEqual(initial_windows, winnr('$'), position .. ' layout must not leak margin windows')
  AssertEqual(initial_popups, len(popup_list()), position .. ' layout must not leak border popups')
endfor

eiwa.Setup({
  command: [agent, 'serve', '--provider', 'placeholder'],
  window: {position: 'float'},
})
eiwa.Open()
var input_windows = WindowsWithFiletype('eiwa-input')
AssertEqual(1, len(input_windows))
var input_pos = win_screenpos(ui.InputWindow())
var history_pos = popup_getpos(ui.HistoryWindow())
AssertEqual(input_pos[1], history_pos.core_col, 'history and input text must align')
AssertEqual(true, history_pos.line + history_pos.height < input_pos[0], 'history must not cover the input')
AssertEqual(true, winwidth(ui.InputWindow()) < &columns, 'float input must have side margins')
setbufline(winbufnr(input_windows[0]), 1, ['draft'])
eiwa.Resize()
AssertEqual('draft', ui.Input(), 'resize must preserve the input draft')
var original_columns = &columns
set columns=100
eiwa.Resize()
AssertEqual(win_screenpos(ui.InputWindow())[1], popup_getpos(ui.HistoryWindow()).core_col, 'resized panels must align')
AssertEqual('draft', ui.Input(), 'terminal resize must preserve the draft')
&columns = original_columns
eiwa.Resize()
win_execute(input_windows[0], 'close!')
sleep 50m
AssertEqual(false, ui.IsOpen(), 'closing the input window must close the interface')
AssertEqual(0, len(WindowsWithFiletype('eiwa-history')), 'closing the input window must remove the history popup')
eiwa.Open()
AssertEqual(1, len(WindowsWithFiletype('eiwa-history')), 'reopen must create one history window')
AssertEqual(1, len(WindowsWithFiletype('eiwa-input')), 'reopen must create one input window')
eiwa.Close()

eiwa.Setup({
  command: [agent, 'serve', '--provider', 'placeholder'],
  window: {position: 'tab'},
})
eiwa.Open()
tabclose! 1
var closed_last_tab = true
try
  eiwa.Close()
catch
  closed_last_tab = false
endtry
AssertEqual(true, closed_last_tab, 'closing Eiwa must work when its tab is the last tab')
AssertEqual(false, ui.IsOpen())

eiwa.Setup({
  command: [agent, 'serve', '--provider', 'placeholder'],
  window: {position: 'float'},
  history: {max_messages: 100},
})
eiwa.Open()
var source_lines = [
  '',
  '  // Print writes to standard output.',
  '// Spaces are added between operands.',
  '',
  'func Print(a ...any) (n int, err error) {',
  "\treturn Fprint(os.Stdout, a...)",
  '}',
  '',
]
# Some Windows terminals send pasted newlines as ordinary Enter keys.
# Such input must remain a draft until the user explicitly requests translation.
feedkeys("i// First line.\<CR>// Second line.\<CR>\<CR>last line\<CR>\<C-\>\<C-n>", 'xt')
AssertEqual(0, len(eiwa.GetMessages()), 'terminal paste must not translate the first line automatically')
AssertEqual("// First line.\n// Second line.\n\nlast line\n", ui.Input(), 'terminal paste must retain every line and blank line')
sleep 200m
AssertEqual(0, len(eiwa.GetMessages()), 'finishing a paste must not submit it')
ui.ClearInput()
cursor(1, 1)
ui.PasteText(join(source_lines, "\r\n"))
AssertEqual(source_lines, getbufline(winbufnr(ui.InputWindow()), 1, '$'), 'Windows paste must preserve lines, blank lines, and indentation')
AssertEqual('idle', eiwa.GetStatus(), 'pasting must not submit a request')
AssertEqual(0, len(eiwa.GetMessages()), 'pasting must not create partial messages')
feedkeys("i\<CR>", 'xt')
AssertEqual(true, WaitFor(() => eiwa.GetStatus() == 'idle', 5000), 'agent response timed out: ' .. string(eiwa.GetMessages()))

var messages = eiwa.GetMessages()
AssertEqual(2, len(messages))
AssertEqual('user', messages[0].role)
AssertEqual(join(source_lines, "\n"), messages[0].content, 'the complete multiline input must be sent in one request')
AssertEqual('assistant', messages[1].role)
AssertEqual('Translation backend is not implemented yet.', messages[1].content)

var history = WindowsWithFiletype('eiwa-history')
AssertEqual(1, len(history))
var rendered = getbufline(winbufnr(history[0]), 1, '$')
AssertEqual('> You', rendered[0], 'history must render the user label')
AssertEqual(source_lines, rendered[1 : len(source_lines)], 'history must preserve original line breaks')
AssertEqual('> Assistant', rendered[len(source_lines) + 2])
ui.Render([{role: 'assistant', content: "first\r\n\tsecond\rthird"}], 'idle')
AssertEqual(['> Assistant', 'first', "\tsecond", 'third', ''], getbufline(winbufnr(history[0]), 1, '$'), 'reply rendering must normalize Windows and legacy line endings')

# A paste in the middle of a line must retain both its prefix and suffix.
setbufline(winbufnr(ui.InputWindow()), 1, 'before-after')
cursor(1, 8)
ui.PasteText("one\ntwo")
AssertEqual("before-one\ntwoafter", ui.Input(), 'multiline insertion must retain surrounding text')

eiwa.Close()

# The commands must work from any script context, including legacy scripts.
Eiwa
AssertEqual(true, ui.IsOpen(), ':Eiwa must open the interface')
AssertEqual(2, len(eiwa.GetMessages()), ':Eiwa must retain the history')
Eiwa
AssertEqual(false, ui.IsOpen(), ':Eiwa must toggle the interface closed')
legacy call eiwa#Open()
AssertEqual(true, ui.IsOpen(), 'legacy eiwa#Open() must work')
EiwaClose
AssertEqual(false, ui.IsOpen(), ':EiwaClose must close the interface')
EiwaClear
AssertEqual(0, len(eiwa.GetMessages()), ':EiwaClear must clear the history')
doautocmd VimResized
doautocmd ColorScheme

eiwa.Shutdown()
AssertEqual(true, WaitFor(() => !process.IsRunning(), 3000), 'agent must stop after shutdown')

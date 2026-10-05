vim9script

# Renders conversation history into a buffer with text properties.

const labels = {
  user: '> You',
  assistant: '> Assistant',
  error: '> Error',
  system: '> System',
}

const highlights = {
  user: 'EiwaUser',
  assistant: 'EiwaAssistant',
  error: 'EiwaError',
  system: 'EiwaSystem',
}

export def SetupHighlights()
  highlight default link EiwaUser Identifier
  highlight default link EiwaAssistant String
  highlight default link EiwaError ErrorMsg
  highlight default link EiwaSystem Comment
  highlight default link EiwaBorder Identifier
  highlight default link EiwaNormal Normal
  for group in values(highlights)
    if index(prop_type_list(), group) < 0
      prop_type_add(group, {highlight: group})
    endif
  endfor
enddef

def ContentLines(content: string): list<string>
  if content == ''
    return ['']
  endif
  return split(substitute(substitute(content, "\r\n", "\n", 'g'), "\r", "\n", 'g'), "\n", 1)
enddef

export def Render(buf: number, messages: list<dict<any>>, status: string)
  if buf <= 0 || !bufexists(buf)
    return
  endif

  var lines: list<string> = []
  var marks: list<dict<any>> = []
  if empty(messages)
    lines = [
      'Enter English text in the input area.',
      'Paste with Ctrl-V, then press the translate key shown below.',
    ]
    marks->add({line: 1, role: 'system'})
  else
    for message in messages
      lines->add(get(labels, message.role, '> ' .. message.role))
      marks->add({line: len(lines), role: message.role})
      lines->extend(ContentLines(message.content))
      lines->add('')
    endfor
  endif

  if status != 'idle'
    lines->add($'[{status}]')
  endif

  setbufvar(buf, '&modifiable', 1)
  silent! deletebufline(buf, 1, '$')
  setbufline(buf, 1, lines)
  prop_clear(1, len(lines), {bufnr: buf})
  for mark in marks
    var text = lines[mark.line - 1]
    if text != ''
      prop_add(mark.line, 1, {
        length: strlen(text),
        type: get(highlights, mark.role, 'EiwaSystem'),
        bufnr: buf,
      })
    endif
  endfor
  setbufvar(buf, '&modifiable', 0)
enddef

vim9script

# Conversation history and request state for eiwa.vim.

var messages: list<dict<any>> = []
var status = 'idle'
var active_request = ''
var max_messages = 100

def Trim()
  while len(messages) > max_messages
    remove(messages, 0)
  endwhile
enddef

export def Configure(opts: dict<any>)
  max_messages = float2nr(opts.max_messages)
  Trim()
enddef

export def Add(role: string, content: string, request_id: string)
  messages->add({role: role, content: content, request_id: request_id})
  Trim()
enddef

export def StartAssistant(request_id: string)
  Add('assistant', '', request_id)
enddef

export def AppendAssistant(request_id: string, content: string)
  for index in range(len(messages) - 1, 0, -1)
    var item = messages[index]
    if item.role == 'assistant' && item.request_id == request_id
      item.content ..= content
      return
    endif
  endfor
  Add('assistant', content, request_id)
enddef

export def AddError(content: string, request_id: string)
  Add('error', content, request_id)
enddef

export def SetStatus(value: string, request_id: string)
  status = value
  active_request = request_id
enddef

export def GetStatus(): string
  return status
enddef

export def GetActiveRequest(): string
  return active_request
enddef

export def GetMessages(): list<dict<any>>
  return deepcopy(messages)
enddef

export def Clear()
  messages = []
  status = 'idle'
  active_request = ''
enddef

vim9script

# Public API of eiwa.vim. Legacy scripts can call these as eiwa#Setup() etc.

import autoload 'eiwa/config.vim'
import autoload 'eiwa/process.vim'
import autoload 'eiwa/render.vim'
import autoload 'eiwa/session.vim'
import autoload 'eiwa/ui.vim'

var configured = false
var sequence = 0

def Render()
  ui.Render(session.GetMessages(), session.GetStatus())
enddef

def Warn(message: string)
  echohl WarningMsg
  echomsg 'Eiwa: ' .. message
  echohl None
enddef

def ProcessError(message: string)
  session.AddError(message, session.GetActiveRequest())
  session.SetStatus('error', '')
  Render()
  echohl ErrorMsg
  echomsg 'Eiwa: ' .. message
  echohl None
enddef

def HandleEvent(event: dict<any>)
  var id = get(event, 'id', '')
  if type(id) != v:t_string
    id = string(id)
  endif
  if id != '' && id != session.GetActiveRequest()
    return
  endif
  var kind = get(event, 'type', '')
  if kind == 'started'
    session.SetStatus('streaming', id)
    session.StartAssistant(id)
  elseif kind == 'assistant_delta'
    session.AppendAssistant(id, get(event, 'content', ''))
  elseif kind == 'assistant_done'
    session.SetStatus('idle', '')
  elseif kind == 'cancelled'
    session.Add('system', 'Request cancelled.', id)
    session.SetStatus('idle', '')
  elseif kind == 'error'
    session.AddError(get(event, 'message', 'Unknown agent error'), id)
    session.SetStatus('error', '')
  endif
  Render()
enddef

def OnExit(code: number)
  var status = session.GetStatus()
  if status == 'streaming' || status == 'submitting'
    session.SetStatus('error', '')
    Render()
  endif
enddef

def EnsureSetup()
  if !configured
    Setup(null)
  endif
enddef

def EnsureProcess(): bool
  return process.Start(config.values.command, {
    on_event: HandleEvent,
    on_error: ProcessError,
    on_exit: OnExit,
  }, config.values.api)
enddef

# Setup(opts) applies the given options. Setup() without arguments applies
# g:eiwa_config when it exists, otherwise the defaults.
export def Setup(opts: any = null): dict<any>
  var values = config.Setup(opts == null ? get(g:, 'eiwa_config', {}) : opts)
  session.Configure(values.history)
  render.SetupHighlights()
  configured = true
  return values
enddef

export def SetupHighlights()
  render.SetupHighlights()
enddef

export def Open()
  EnsureSetup()
  ui.Open(config.values, {
    submit: () => Submit(),
    cancel: Cancel,
    close: Close,
    render: Render,
    messages: session.GetMessages,
    status: session.GetStatus,
  })
enddef

export def Close()
  ui.Close()
enddef

export def Toggle()
  if ui.IsOpen()
    Close()
  else
    Open()
  endif
enddef

export def Submit(content: string = ''): bool
  EnsureSetup()
  var status = session.GetStatus()
  if status == 'submitting' || status == 'streaming'
    Warn('a request is already running')
    return false
  endif

  var text = content != '' ? content : ui.Input()
  if trim(text) == ''
    return false
  endif
  if !EnsureProcess()
    return false
  endif

  sequence += 1
  var request_id = trim(reltimestr(reltime()))->substitute('\.', '', 'g') .. '-' .. sequence
  session.Add('user', text, request_id)
  session.SetStatus('submitting', request_id)
  ui.ClearInput()
  Render()

  var err = process.Send({type: 'submit', id: request_id, content: text})
  if err != ''
    ProcessError(err)
    return false
  endif
  return true
enddef

export def Cancel(): bool
  var request_id = session.GetActiveRequest()
  if request_id == ''
    return false
  endif
  var err = process.Send({type: 'cancel', id: request_id})
  if err != ''
    ProcessError(err)
    return false
  endif
  return true
enddef

export def Clear()
  session.Clear()
  Render()
enddef

export def NewSession()
  Cancel()
  Clear()
enddef

export def GetMessages(): list<dict<any>>
  return session.GetMessages()
enddef

export def GetStatus(): string
  return session.GetStatus()
enddef

export def Resize()
  ui.Resize()
enddef

export def Shutdown()
  process.Shutdown()
enddef

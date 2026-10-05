vim9script

# Requires the local eiwa API. Run from the plugin root:
#   vim -es -N -u tests/minimal.vim -S tests/live_api.vim

import autoload 'eiwa.vim'
import autoload 'eiwa/process.vim'

def WaitFor(Condition: func(): bool, timeout: number): bool
  var waited = 0
  while waited < timeout
    if Condition()
      return true
    endif
    sleep 20m
    waited += 20
  endwhile
  return Condition()
enddef

try
  if empty(process.ResolveCommand(null))
    throw 'agent must be discovered automatically'
  endif
  eiwa.Setup({api: {glossary: {'working tree': '作業ツリー'}}})
  eiwa.Open()
  if !eiwa.Submit('Run `git status` to inspect the working tree.')
    throw 'submit failed'
  endif
  if !WaitFor(() => eiwa.GetStatus() == 'idle' || eiwa.GetStatus() == 'error', 90000)
    throw 'translation timed out'
  endif
  if eiwa.GetStatus() != 'idle'
    throw string(eiwa.GetMessages())
  endif
  var messages = eiwa.GetMessages()
  var translated = messages[-1].content
  if stridx(translated, '作業ツリー') < 0 || stridx(translated, '`git status`') < 0
    throw 'unexpected translation: ' .. translated
  endif
  verbose echo 'Live Vim translation: ' .. translated
  eiwa.Close()
  eiwa.Shutdown()
catch
  verbose echo 'FAILED: ' .. v:exception .. "\n" .. v:throwpoint
  cquit 1
endtry
qall!

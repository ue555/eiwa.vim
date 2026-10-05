vim9script

# Lifecycle of the eiwa-agent child process and JSON Lines transport.

const plugin_root = fnamemodify(expand('<sfile>:p'), ':h:h:h')

var job_handle: job = null_job
var callbacks: dict<func> = {}
var stderr_lines: list<string> = []

def Platform(): list<string>
  var os_name: string
  var machine: string
  if has('win32')
    os_name = 'windows'
    machine = $PROCESSOR_ARCHITECTURE
  else
    os_name = tolower(trim(system('uname -s')))
    machine = trim(system('uname -m'))
  endif
  const architectures = {
    x86_64: 'amd64',
    amd64: 'amd64',
    AMD64: 'amd64',
    aarch64: 'arm64',
    arm64: 'arm64',
    ARM64: 'arm64',
  }
  return [os_name, get(architectures, machine, tolower(machine))]
enddef

export def ResolveCommand(configured: any): list<string>
  if type(configured) == v:t_list
    return deepcopy(configured)
  endif
  if type(configured) == v:t_string && configured != ''
    return [configured, 'serve']
  endif

  var path = exepath('eiwa-agent')
  if path != ''
    return [path, 'serve']
  endif

  var [os_name, architecture] = Platform()
  var suffix = os_name == 'windows' ? '.exe' : ''
  var candidates = [
    plugin_root .. '/bin/eiwa-agent-' .. os_name .. '-' .. architecture .. suffix,
    plugin_root .. '/bin/eiwa-agent' .. suffix,
  ]
  for candidate in candidates
    if executable(candidate)
      return [candidate, 'serve']
    endif
  endfor
  return []
enddef

def OnStdout(channel: channel, line: string)
  if line == ''
    return
  endif
  var event: any
  try
    event = json_decode(line)
  catch
    event = null
  endtry
  if type(event) != v:t_dict
    if has_key(callbacks, 'on_error')
      callbacks.on_error('invalid agent response: ' .. line)
    endif
    return
  endif
  if has_key(callbacks, 'on_event')
    callbacks.on_event(event)
  endif
enddef

def OnStderr(channel: channel, line: string)
  if line != ''
    stderr_lines->add(line)
  endif
enddef

def OnExit(finished: job, code: number)
  var previous = callbacks
  job_handle = null_job
  callbacks = {}
  if code != 0 && has_key(previous, 'on_error')
    var detail = trim(join(stderr_lines, "\n"))
    previous.on_error($'eiwa-agent exited with code {code}' .. (detail != '' ? ': ' .. detail : ''))
  endif
  if has_key(previous, 'on_exit')
    previous.on_exit(code)
  endif
enddef

export def Start(configured: any, handlers: dict<func>, api: dict<any>): bool
  if IsRunning()
    return true
  endif

  var command = ResolveCommand(configured)
  if empty(command) || !executable(command[0])
    handlers.on_error('eiwa-agent was not found. Build it with scripts/build.sh (scripts/build.ps1 on Windows).')
    return false
  endif

  callbacks = handlers
  stderr_lines = []
  var options: dict<any> = {
    in_mode: 'nl',
    out_mode: 'nl',
    err_mode: 'nl',
    out_cb: OnStdout,
    err_cb: OnStderr,
    exit_cb: OnExit,
    noblock: 1,
  }
  if !empty(api)
    options.env = {
      EIWA_API_URL: api.endpoint,
      EIWA_API_TIMEOUT: string(api.timeout) .. 's',
      EIWA_API_STYLE: api.style,
      EIWA_API_GLOSSARY: json_encode(api.glossary),
    }
  endif

  job_handle = job_start(command, options)
  if job_status(job_handle) != 'run'
    job_handle = null_job
    callbacks = {}
    handlers.on_error('eiwa-agent failed to start: ' .. join(command, ' '))
    return false
  endif
  return true
enddef

# Returns an empty string on success, otherwise the error message.
export def Send(message: dict<any>): string
  if !IsRunning()
    return 'eiwa-agent is not running'
  endif
  try
    ch_sendraw(job_handle, json_encode(message) .. "\n")
  catch
    return v:exception
  endtry
  return ''
enddef

export def Shutdown()
  if !IsRunning()
    return
  endif
  Send({type: 'shutdown'})
enddef

export def IsRunning(): bool
  return job_handle != null_job && job_status(job_handle) == 'run'
enddef

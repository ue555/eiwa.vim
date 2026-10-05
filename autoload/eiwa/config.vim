vim9script

# Configuration defaults and validation for eiwa.vim.

const defaults: dict<any> = {
  command: null,
  api: {
    endpoint: 'http://127.0.0.1:8000/translate',
    timeout: 90,
    style: 'source',
    glossary: {},
  },
  window: {
    position: 'float',
    width: 0.8,
    height: 0.8,
    split_width: 0.4,
    split_height: 0.35,
    input_height: 3,
    border: 'rounded',
  },
  history: {
    max_messages: 100,
  },
  keymaps: {
    submit: '<CR>',
    cancel: '<C-c>',
    close: 'q',
  },
}

export var values: dict<any> = deepcopy(defaults)

def DeepExtend(base: dict<any>, overrides: dict<any>): dict<any>
  var result = deepcopy(base)
  for [key, value] in items(overrides)
    if type(value) == v:t_dict && type(get(result, key, null)) == v:t_dict
      result[key] = DeepExtend(result[key], value)
    else
      result[key] = deepcopy(value)
    endif
  endfor
  return result
enddef

def IsNumber(value: any): bool
  return type(value) == v:t_number || type(value) == v:t_float
enddef

def Ratio(name: string, value: any)
  if !IsNumber(value) || value <= 0 || value > 1
    throw $'eiwa: {name} must be between 0 and 1'
  endif
enddef

export def Setup(opts: any): dict<any>
  var overrides = opts == null ? {} : opts
  if type(overrides) != v:t_dict
    throw 'eiwa: setup options must be a dictionary'
  endif
  var merged = DeepExtend(defaults, overrides)

  if type(merged.api.endpoint) != v:t_string || merged.api.endpoint !~ '^https\?://'
    throw 'eiwa: api.endpoint must be an HTTP or HTTPS URL'
  endif
  if !IsNumber(merged.api.timeout) || merged.api.timeout <= 0
    throw 'eiwa: api.timeout must be positive seconds'
  endif
  if index(['source', 'polite', 'plain'], merged.api.style) < 0
    throw 'eiwa: api.style must be source, polite, or plain'
  endif
  if type(merged.api.glossary) != v:t_dict
    throw 'eiwa: api.glossary must be a dictionary'
  endif
  for [term, translation] in items(merged.api.glossary)
    if type(translation) != v:t_string
      throw 'eiwa: api.glossary must contain string values'
    endif
  endfor

  if index(['float', 'right', 'bottom', 'tab'], merged.window.position) < 0
    throw 'eiwa: window.position must be float, right, bottom, or tab'
  endif
  Ratio('window.width', merged.window.width)
  Ratio('window.height', merged.window.height)
  Ratio('window.split_width', merged.window.split_width)
  Ratio('window.split_height', merged.window.split_height)
  if type(merged.window.input_height) != v:t_number || merged.window.input_height < 1
    throw 'eiwa: window.input_height must be a positive integer'
  endif
  if type(merged.window.border) != v:t_string
    throw 'eiwa: window.border must be a string'
  endif
  if !IsNumber(merged.history.max_messages) || merged.history.max_messages < 1
    throw 'eiwa: history.max_messages must be a positive number'
  endif
  for key in ['submit', 'cancel', 'close']
    if type(merged.keymaps[key]) != v:t_string || merged.keymaps[key] == ''
      throw $'eiwa: keymaps.{key} must be a non-empty string'
    endif
  endfor
  if merged.command != null && type(merged.command) != v:t_string && type(merged.command) != v:t_list
    throw 'eiwa: command must be a string or a list'
  endif

  values = merged
  return values
enddef

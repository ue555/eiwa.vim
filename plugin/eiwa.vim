vim9script

# eiwa.vim: English-to-Japanese translation UI for Vim
# License: MIT

if exists('g:loaded_eiwa_vim')
  finish
endif
g:loaded_eiwa_vim = 1

if !has('vim9script') || !has('job') || !has('channel') || !has('popupwin') || !has('textprop')
  echoerr 'eiwa.vim requires Vim 9.0 or later with +job, +channel, +popupwin, and +textprop'
  finish
endif

# Autoload functions are referenced by their eiwa#Name form so that the
# commands and autocommands work regardless of the caller's script context.
command! -bar Eiwa call eiwa#Toggle()
command! -bar EiwaSubmit call eiwa#Submit()
command! -bar EiwaClose call eiwa#Close()
command! -bar EiwaClear call eiwa#Clear()
command! -bar EiwaCancel call eiwa#Cancel()
command! -bar EiwaNewSession call eiwa#NewSession()

augroup EiwaVim
  autocmd!
  autocmd VimResized * call eiwa#Resize()
  autocmd VimLeavePre * call eiwa#Shutdown()
  autocmd ColorScheme * call eiwa#SetupHighlights()
augroup END

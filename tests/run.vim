vim9script

try
  source tests/eiwa_test.vim
catch
  verbose echo 'FAILED: ' .. v:exception .. "\n" .. v:throwpoint
  cquit 1
endtry

verbose echo 'eiwa.vim tests passed'
qall!

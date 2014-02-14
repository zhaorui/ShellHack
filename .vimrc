syntax on
set nu
set ru
set hlsearch
set ic
set tags=./tags,../tags,../../tags,../../../tags
set softtabstop=4 shiftwidth=4 expandtab
set autoindent

" In many terminal emulators the mouse works just fine, thus enable it.
if has('mouse')
  set mouse=a
endif

if has("autocmd")

  " Enable file type detection.
  " Use the default filetype settings, so that mail gets 'tw' set to 72,
  " 'cindent' is on in C files, etc.
  " Also load indent files, to automatically do language-dependent indenting.
  filetype plugin indent on

endif

syntax on
set nu
set ru
set hlsearch
set incsearch "show the next match while entering a search
set ic "ignore case
set smartcase "smart case, when the search pattern contain capital word, it would be case sensitive
set tags=./tags,../tags,../../tags,../../../tags,../../../../tags,../../../../../tags
set softtabstop=4 shiftwidth=4 expandtab
set autoindent
set nows "set nowrapscan


""""""""""""""""""""""""""""""
" Tag list (ctags)
""""""""""""""""""""""""""""""
let Tlist_Ctags_Cmd = '/usr/local/bin/ctags'
let Tlist_Show_One_File = 1            "不同时显示多个文件的tag，只显示当前文件的
let Tlist_Exit_OnlyWindow = 1          "如果taglist窗口是最后一个窗口，则退出vim
"let Tlist_Use_Right_Window = 1         "在右侧窗口中显示taglist窗口 


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

function! OnlineDoc()
    "let s:browser = "firefox"
    let s:browser = "open"
    let s:wordUnderCursor = expand("<cword>")
 
    if &ft == "cpp" || &ft == "c" || &ft == "ruby" || &ft == "php" || &ft == "python"
    let s:url = "http://www.google.com/codesearch?q=".s:wordUnderCursor."+lang:".&ft
    elseif &ft == "gvim"
    let s:url = "http://www.google.com/codesearch?q=".s:wordUnderCursor
    else
    return
    endif
 
    let s:cmd = "silent !" . s:browser . " " . s:url
    execute s:cmd
    redraw!
endfunction
 
" online doc search
map <ESC>k :call OnlineDoc()<CR>



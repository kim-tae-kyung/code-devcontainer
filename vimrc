" General settings
set nocompatible             " Disable compatibility mode with old vi
set encoding=utf-8           " Set default encoding to UTF-8
set fencs=utf-8              " Fallback encodings
set fileencoding=utf-8       " File encoding to UTF-8
set tenc=utf-8               " Terminal encoding to UTF-8

" Appearance and interface
set number                   " Show line numbers
set ruler                    " Show the cursor position
set showcmd                  " Display incomplete commands
set cursorline               " Highlight the current line
set wildmenu                 " Command-line completion in a menu
set lazyredraw               " Faster scrolling
set showmatch                " Highlight matching parenthesis
set wrap                     " Enable wrapping of lines

" Indentation and tabs
set autoindent               " Automatic indentation
set smartindent              " Smart auto-indenting
set shiftwidth=4             " Number of spaces to use for each step of (auto)indent
set tabstop=4                " Number of spaces that a <Tab> in the file counts for
set expandtab                " Use spaces instead of tabs
set softtabstop=4            " Number of spaces tabs count for in insert mode
set backspace=eol,start,indent " Allow backspace in insert mode

" Backup and swap files
set nobackup                 " Disable backup file
set nowritebackup            " Disable backup before overwriting
set noswapfile               " Disable swap file

" Visual settings
set visualbell               " Use visual bell instead of beeping
set hidden                   "
set autoread                 " Auto-reload when file changes
syntax on                    " Enable syntax highlighting
filetype indent on           " Enable file-type specific indentation
colorscheme koehler          " Set colorscheme

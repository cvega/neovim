" Tests for startup.

source shared.vim

" Check that loading startup.vim works.
func Test_startup_script()
  throw 'skipped: Nvim does not need defaults.vim'
  set compatible
  source $VIMRUNTIME/defaults.vim

  call assert_equal(0, &compatible)
endfunc

" Verify the order in which plugins are loaded:
" 1. plugins in non-after directories
" 2. packages
" 3. plugins in after directories
func Test_after_comes_later()
  if !has('packages')
    return
  endif
  let before = [
	\ 'set nocp viminfo+=nviminfo',
	\ 'set guioptions+=M',
	\ 'let $HOME = "/does/not/exist"',
	\ 'set loadplugins',
	\ 'set rtp=Xhere,Xafter',
	\ 'set packpath=Xhere,Xafter',
	\ 'set nomore',
	\ ]
  let after = [
	\ 'redir! > Xtestout',
	\ 'scriptnames',
	\ 'redir END',
	\ 'quit',
	\ ]
  call mkdir('Xhere/plugin', 'p')
  call writefile(['let done = 1'], 'Xhere/plugin/here.vim')
  call mkdir('Xhere/pack/foo/start/foobar/plugin', 'p')
  call writefile(['let done = 1'], 'Xhere/pack/foo/start/foobar/plugin/foo.vim')

  call mkdir('Xafter/plugin', 'p')
  call writefile(['let done = 1'], 'Xafter/plugin/later.vim')

  if RunVim(before, after, '')

    let lines = readfile('Xtestout')
    let expected = ['Xbefore.vim', 'here.vim', 'foo.vim', 'later.vim', 'Xafter.vim']
    let found = []
    for line in lines
      for one in expected
	if line =~ one
	  call add(found, one)
	endif
      endfor
    endfor
    call assert_equal(expected, found)
  endif

  call delete('Xtestout')
  call delete('Xhere', 'rf')
  call delete('Xafter', 'rf')
endfunc

func Test_help_arg()
  if !has('unix') && has('gui')
    " this doesn't work with gvim on MS-Windows
    return
  endif
  if RunVim([], [], '--help >Xtestout')
    let lines = readfile('Xtestout')
    call assert_true(len(lines) > 20)
    call assert_match('Usage:', lines[0])

    " check if  couple of lines are there
    let found = []
    for line in lines
      if line =~ '-R.*Read-only mode'
        call add(found, 'Readonly mode')
      endif
      " Watch out for a second --version line in the Gnome version.
      if line =~ '--version.*Print version information'
        call add(found, "--version")
      endif
    endfor
    call assert_equal(['Readonly mode', '--version'], found)
  endif
  call delete('Xtestout')
endfunc

func Test_compatible_args()
  throw "skipped: Nvim is always 'nocompatible'"
  let after = [
	\ 'call writefile([string(&compatible)], "Xtestout")',
	\ 'set viminfo+=nviminfo',
	\ 'quit',
	\ ]
  if RunVim([], after, '-C')
    let lines = readfile('Xtestout')
    call assert_equal('1', lines[0])
  endif

  if RunVim([], after, '-N')
    let lines = readfile('Xtestout')
    call assert_equal('0', lines[0])
  endif

  call delete('Xtestout')
endfunc

func Test_file_args()
  let after = [
	\ 'call writefile(argv(), "Xtestout")',
	\ 'qall',
	\ ]
  if RunVim([], after, '')
    let lines = readfile('Xtestout')
    call assert_equal(0, len(lines))
  endif

  if RunVim([], after, 'one')
    let lines = readfile('Xtestout')
    call assert_equal(1, len(lines))
    call assert_equal('one', lines[0])
  endif

  if RunVim([], after, 'one two three')
    let lines = readfile('Xtestout')
    call assert_equal(3, len(lines))
    call assert_equal('one', lines[0])
    call assert_equal('two', lines[1])
    call assert_equal('three', lines[2])
  endif

  if RunVim([], after, 'one -c echo two')
    let lines = readfile('Xtestout')
    call assert_equal(2, len(lines))
    call assert_equal('one', lines[0])
    call assert_equal('two', lines[1])
  endif

  if RunVim([], after, 'one -- -c echo two')
    let lines = readfile('Xtestout')
    call assert_equal(4, len(lines))
    call assert_equal('one', lines[0])
    call assert_equal('-c', lines[1])
    call assert_equal('echo', lines[2])
    call assert_equal('two', lines[3])
  endif

  call delete('Xtestout')
endfunc

func Test_startuptime()
  if !has('startuptime')
    return
  endif
  let after = ['qall']
  if RunVim([], after, '--startuptime Xtestout one')
    let lines = readfile('Xtestout')
    let expected = ['parsing arguments', 'inits 3', 'opening buffers']
    let found = []
    for line in lines
      for exp in expected
	if line =~ exp
	  call add(found, exp)
	endif
      endfor
    endfor
    call assert_equal(expected, found)
  endif
  call delete('Xtestout')
endfunc

func Test_read_stdin()
  let after = [
	\ 'write Xtestout',
	\ 'quit!',
	\ ]
  if RunVimPiped([], after, '-', 'echo something | ')
    let lines = readfile('Xtestout')
    " MS-Windows adds a space after the word
    call assert_equal(['something'], split(lines[0]))
  endif
  call delete('Xtestout')
endfunc

func Test_progpath()
  " Tests normally run with "./vim" or "../vim", these must have been expanded
  " to a full path.
  if has('unix')
    call assert_equal('/', v:progpath[0])
  elseif has('win32')
    call assert_equal(':', v:progpath[1])
    call assert_match('[/\\]', v:progpath[2])
  endif

  " Only expect "vim" to appear in v:progname.
  call assert_match('vim\c', v:progname)
endfunc

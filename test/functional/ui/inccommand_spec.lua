local helpers = require('test.functional.helpers')(after_each)
local Screen = require('test.functional.ui.screen')
local clear = helpers.clear
local command = helpers.command
local curbufmeths = helpers.curbufmeths
local eq = helpers.eq
local eval = helpers.eval
local feed_command = helpers.feed_command
local expect = helpers.expect
local feed = helpers.feed
local insert = helpers.insert
local meths = helpers.meths
local neq = helpers.neq
local ok = helpers.ok
local source = helpers.source
local wait = helpers.wait

local default_text = [[
  Inc substitution on
  two lines
]]

local function common_setup(screen, inccommand, text)
  if screen then
    command("syntax on")
    command("set nohlsearch")
    command("hi Substitute guifg=red guibg=yellow")
    screen:attach()
    screen:set_default_attr_ids({
      [1]  = {foreground = Screen.colors.Fuchsia},
      [2]  = {foreground = Screen.colors.Brown, bold = true},
      [3]  = {foreground = Screen.colors.SlateBlue},
      [4]  = {bold = true, foreground = Screen.colors.SlateBlue},
      [5]  = {foreground = Screen.colors.DarkCyan},
      [6]  = {bold = true},
      [7]  = {underline = true, bold = true, foreground = Screen.colors.SlateBlue},
      [8]  = {foreground = Screen.colors.Slateblue, underline = true},
      [9]  = {background = Screen.colors.Yellow},
      [10] = {reverse = true},
      [11] = {reverse = true, bold=true},
      [12] = {foreground = Screen.colors.Red, background = Screen.colors.Yellow},
      [13] = {bold = true, foreground = Screen.colors.SeaGreen},
      [14] = {foreground = Screen.colors.White, background = Screen.colors.Red},
      [15] = {bold=true, foreground=Screen.colors.Blue},
      [16] = {background=Screen.colors.Grey90},  -- cursorline
      vis  = {background=Screen.colors.LightGrey}
    })
  end

  command("set inccommand=" .. (inccommand and inccommand or ""))

  if text then
    insert(text)
  end
end

describe(":substitute, inccommand=split does not trigger preview", function()
  before_each(function()
    clear()
    common_setup(nil, "split", default_text)
  end)

  it("if invoked by a script ", function()
    source('%s/tw/MO/g')
    wait()
    eq(1, eval("bufnr('$')"))

    -- sanity check: assert the buffer state
    expect(default_text:gsub("tw", "MO"))
  end)

  it("if invoked by feedkeys()", function()
    -- in a script...
    source([[:call feedkeys(":%s/tw/MO/g\<CR>")]])
    wait()
    -- or interactively...
    feed([[:call feedkeys(":%s/tw/MO/g\<CR>")<CR>]])
    wait()
    eq(1, eval("bufnr('$')"))

    -- sanity check: assert the buffer state
    expect(default_text:gsub("tw", "MO"))
  end)
end)

describe(":substitute, 'inccommand' preserves", function()
   if helpers.pending_win32(pending) then return end

  before_each(clear)

  it('listed buffers (:ls)', function()
    local screen = Screen.new(30,10)
    common_setup(screen, "split", "ABC")

    feed_command("%s/AB/BA/")
    feed_command("ls")

    screen:expect([[
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      :ls                           |
        1 %a + "[No Name]"          |
                line 1              |
      {13:Press ENTER or type command to}|
      {13: continue}^                     |
    ]])
  end)

  for _, case in pairs{"", "split", "nosplit"} do
    it("various delimiters (inccommand="..case..")", function()
      insert(default_text)
      feed_command("set inccommand=" .. case)

      local delims = { '/', '#', ';', '%', ',', '@', '!', ''}
      for _,delim in pairs(delims) do
        feed_command("%s"..delim.."lines"..delim.."LINES"..delim.."g")
        expect([[
          Inc substitution on
          two LINES
          ]])
        feed_command("undo")
      end
    end)
  end

  for _, case in pairs{"", "split", "nosplit"} do
    it("'undolevels' (inccommand="..case..")", function()
      feed_command("set undolevels=139")
      feed_command("setlocal undolevels=34")
      feed_command("set inccommand=" .. case)
      insert("as")
      feed(":%s/as/glork/<enter>")
      eq(meths.get_option('undolevels'), 139)
      eq(curbufmeths.get_option('undolevels'), 34)
    end)
  end

  for _, case in ipairs({"", "split", "nosplit"}) do
    it("empty undotree() (inccommand="..case..")", function()
      feed_command("set undolevels=1000")
      feed_command("set inccommand=" .. case)
      local expected_undotree = eval("undotree()")

      -- Start typing an incomplete :substitute command.
      feed([[:%s/e/YYYY/g]])
      wait()
      -- Cancel the :substitute.
      feed([[<C-\><C-N>]])

      -- The undo tree should be unchanged.
      eq(expected_undotree, eval("undotree()"))
      eq({}, eval("undotree()")["entries"])
    end)
  end

  for _, case in ipairs({"", "split", "nosplit"}) do
    it("undotree() with branches (inccommand="..case..")", function()
      feed_command("set undolevels=1000")
      feed_command("set inccommand=" .. case)
      -- Make some changes.
      feed([[isome text 1<C-\><C-N>]])
      feed([[osome text 2<C-\><C-N>]])
      -- Add an undo branch.
      feed([[u]])
      -- More changes, more undo branches.
      feed([[osome text 3<C-\><C-N>]])
      feed([[AX<C-\><C-N>]])
      feed([[...]])
      feed([[uu]])
      feed([[osome text 4<C-\><C-N>]])
      feed([[u<C-R>u]])
      feed([[osome text 5<C-\><C-N>]])
      expect([[
        some text 1
        some text 3XX
        some text 5]])
      local expected_undotree = eval("undotree()")
      eq(5, #expected_undotree["entries"])  -- sanity

      -- Start typing an incomplete :substitute command.
      feed([[:%s/e/YYYY/g]])
      wait()
      -- Cancel the :substitute.
      feed([[<C-\><C-N>]])

      -- The undo tree should be unchanged.
      eq(expected_undotree, eval("undotree()"))
    end)
  end

  for _, case in pairs{"", "split", "nosplit"} do
    it("b:changedtick (inccommand="..case..")", function()
      feed_command("set inccommand=" .. case)
      feed([[isome text 1<C-\><C-N>]])
      feed([[osome text 2<C-\><C-N>]])
      local expected_tick = eval("b:changedtick")
      ok(expected_tick > 0)

      expect([[
        some text 1
        some text 2]])
      feed(":%s/e/XXX/")
      wait()

      eq(expected_tick, eval("b:changedtick"))
    end)
  end

  for _, case in pairs{"", "split", "nosplit"} do
    it("visual selection for non-previewable command (inccommand="..case..") #5888", function()
      local screen = Screen.new(30,10)
      common_setup(screen, case, default_text)
      feed('1G2V')

      feed(':s')
      screen:expect([[
        {vis:Inc substitution on}           |
        t{vis:wo lines}                     |
                                      |
        {15:~                             }|
        {15:~                             }|
        {15:~                             }|
        {15:~                             }|
        {15:~                             }|
        {15:~                             }|
        :'<,'>s^                       |
      ]])

      feed('o')
      screen:expect([[
        {vis:Inc substitution on}           |
        t{vis:wo lines}                     |
                                      |
        {15:~                             }|
        {15:~                             }|
        {15:~                             }|
        {15:~                             }|
        {15:~                             }|
        {15:~                             }|
        :'<,'>so^                      |
      ]])
    end)
  end

end)

describe(":substitute, 'inccommand' preserves undo", function()
   if helpers.pending_win32(pending) then return end

  local cases = { "", "split", "nosplit" }

  local substrings = {
    ":%s/1",
    ":%s/1/",
    ":%s/1/<bs>",
    ":%s/1/a",
    ":%s/1/a<bs>",
    ":%s/1/ax",
    ":%s/1/ax<bs>",
    ":%s/1/ax<bs><bs>",
    ":%s/1/ax<bs><bs><bs>",
    ":%s/1/ax/",
    ":%s/1/ax/<bs>",
    ":%s/1/ax/<bs>/",
    ":%s/1/ax/g",
    ":%s/1/ax/g<bs>",
    ":%s/1/ax/g<bs><bs>"
  }

  local function test_sub(substring, split, redoable)
    clear()
    feed_command("set inccommand=" .. split)

    insert("1")
    feed("o2<esc>")
    feed_command("undo")
    feed("o3<esc>")
    if redoable then
      feed("o4<esc>")
      feed_command("undo")
    end
    feed(substring.. "<enter>")
    feed_command("undo")

    feed("g-")
    expect([[
      1
      2]])

    feed("g+")
    expect([[
      1
      3]])
  end

  local function test_notsub(substring, split, redoable)
    clear()
    feed_command("set inccommand=" .. split)

    insert("1")
    feed("o2<esc>")
    feed_command("undo")
    feed("o3<esc>")
    if redoable then
      feed("o4<esc>")
      feed_command("undo")
    end
    feed(substring .. "<esc>")

    feed("g-")
    expect([[
      1
      2]])

    feed("g+")
    expect([[
      1
      3]])

    if redoable then
      feed("<c-r>")
      expect([[
        1
        3
        4]])
    end
  end


  local function test_threetree(substring, split)
    clear()
    feed_command("set inccommand=" .. split)

    insert("1")
    feed("o2<esc>")
    feed("o3<esc>")
    feed("uu")
    feed("oa<esc>")
    feed("ob<esc>")
    feed("uu")
    feed("oA<esc>")
    feed("oB<esc>")

    -- This is the undo tree (x-Axis is timeline), we're at B now
    --    ----------------A - B
    --   /
    --  | --------a - b
    --  |/
    --  1 - 2 - 3

    feed("2u")
    feed(substring .. "<esc>")
    expect([[
      1]])
    feed("g-")
    expect([[
      ]])
    feed("g+")
    expect([[
      1]])
    feed("<c-r>")
    expect([[
      1
      A]])

    feed("g-") -- go to b
    feed("2u")
    feed(substring .. "<esc>")
    feed("<c-r>")
    expect([[
      1
      a]])

    feed("g-") -- go to 3
    feed("2u")
    feed(substring .. "<esc>")
    feed("<c-r>")
    expect([[
      1
      2]])
  end

  it("at a non-leaf of the undo tree", function()
   for _, case in pairs(cases) do
     for _, str in pairs(substrings) do
       for _, redoable in pairs({true}) do
         test_sub(str, case, redoable)
       end
     end
   end
  end)

  it("at a leaf of the undo tree", function()
    for _, case in pairs(cases) do
      for _, str in pairs(substrings) do
        for _, redoable in pairs({false}) do
          test_sub(str, case, redoable)
        end
      end
    end
  end)

  it("when interrupting substitution", function()
    for _, case in pairs(cases) do
      for _, str in pairs(substrings) do
        for _, redoable in pairs({true,false}) do
          test_notsub(str, case, redoable)
        end
      end
    end
  end)

  it("in a complex undo scenario", function()
    for _, case in pairs(cases) do
      for _, str in pairs(substrings) do
        test_threetree(str, case)
      end
    end
  end)

  it('with undolevels=0', function()
    for _, case in pairs(cases) do
      clear()
      common_setup(nil, case, default_text)
      feed_command("set undolevels=0")

      feed("1G0")
      insert("X")
      feed(":%s/tw/MO/<esc>")
      feed_command("undo")
      expect(default_text)
      feed_command("undo")
      expect(default_text:gsub("Inc", "XInc"))
      feed_command("undo")

      feed_command("%s/tw/MO/g")
      expect(default_text:gsub("tw", "MO"))
      feed_command("undo")
      expect(default_text)
      feed_command("undo")
      expect(default_text:gsub("tw", "MO"))
    end
  end)

  it('with undolevels=1', function()
    local screen = Screen.new(20,10)

    for _, case in pairs(cases) do
      clear()
      common_setup(screen, case, default_text)
      feed_command("set undolevels=1")

      feed("1G0")
      insert("X")
      feed("IY<esc>")
      feed(":%s/tw/MO/<esc>")
      -- feed_command("undo") here would cause "Press ENTER".
      feed("u")
      expect(default_text:gsub("Inc", "XInc"))
      feed("u")
      expect(default_text)

      feed(":%s/tw/MO/g<enter>")
      feed(":%s/MO/GO/g<enter>")
      feed(":%s/GO/NO/g<enter>")
      feed("u")
      expect(default_text:gsub("tw", "GO"))
      feed("u")
      expect(default_text:gsub("tw", "MO"))
      feed("u")

      if case == "split" then
        screen:expect([[
          Inc substitution on |
          ^MOo lines           |
                              |
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          Already ...t change |
        ]])
      else
        screen:expect([[
          Inc substitution on |
          ^MOo lines           |
                              |
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          Already ...t change |
        ]])
      end
    end
    screen:detach()
  end)

  it('with undolevels=2', function()
    local screen = Screen.new(20,10)

    for _, case in pairs(cases) do
      clear()
      common_setup(screen, case, default_text)
      feed_command("set undolevels=2")

      feed("2GAx<esc>")
      feed("Ay<esc>")
      feed("Az<esc>")
      feed(":%s/tw/AR<esc>")
      -- feed_command("undo") here would cause "Press ENTER".
      feed("u")
      expect(default_text:gsub("lines", "linesxy"))
      feed("u")
      expect(default_text:gsub("lines", "linesx"))
      feed("u")
      expect(default_text)
      feed("u")

      if case == "split" then
        screen:expect([[
          Inc substitution on |
          two line^s           |
                              |
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          Already ...t change |
        ]])
      else
        screen:expect([[
          Inc substitution on |
          two line^s           |
                              |
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          Already ...t change |
        ]])
      end

      feed(":%s/tw/MO/g<enter>")
      feed(":%s/MO/GO/g<enter>")
      feed(":%s/GO/NO/g<enter>")
      feed(":%s/NO/LO/g<enter>")
      feed("u")
      expect(default_text:gsub("tw", "NO"))
      feed("u")
      expect(default_text:gsub("tw", "GO"))
      feed("u")
      expect(default_text:gsub("tw", "MO"))
      feed("u")

      if case == "split" then
        screen:expect([[
          Inc substitution on |
          ^MOo lines           |
                              |
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          Already ...t change |
        ]])
      else
        screen:expect([[
          Inc substitution on |
          ^MOo lines           |
                              |
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          Already ...t change |
        ]])
      end
      screen:detach()
    end
  end)

  it('with undolevels=-1', function()
    local screen = Screen.new(20,10)

    for _, case in pairs(cases) do
      clear()
      common_setup(screen, case, default_text)

      feed_command("set undolevels=-1")
      feed(":%s/tw/MO/g<enter>")
      -- feed_command("undo") here will result in a "Press ENTER" prompt
      feed("u")
      if case == "split" then
        screen:expect([[
          Inc substitution on |
          ^MOo lines           |
                              |
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          Already ...t change |
        ]])
      else
        screen:expect([[
          Inc substitution on |
          ^MOo lines           |
                              |
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          {15:~                   }|
          Already ...t change |
        ]])
      end

      -- repeat with an interrupted substitution
      clear()
      common_setup(screen, case, default_text)

      feed_command("set undolevels=-1")
      feed("1G")
      feed("IL<esc>")
      feed(":%s/tw/MO/g<esc>")
      feed("u")

      screen:expect([[
        ^LInc substitution on|
        two lines           |
                            |
        {15:~                   }|
        {15:~                   }|
        {15:~                   }|
        {15:~                   }|
        {15:~                   }|
        {15:~                   }|
        Already ...t change |
      ]])
    end
    screen:detach()
  end)

end)

describe(":substitute, inccommand=split", function()
  if helpers.pending_win32(pending) then return end

  local screen = Screen.new(30,15)

  before_each(function()
    clear()
    common_setup(screen, "split", default_text .. default_text)
  end)

  after_each(function()
    screen:detach()
  end)

  it("preserves 'modified' buffer flag", function()
    feed_command("set nomodified")
    feed(":%s/tw")
    screen:expect([[
      Inc substitution on           |
      two lines                     |
                                    |
      {15:~                             }|
      {15:~                             }|
      {11:[No Name]                     }|
      |2| two lines                 |
      |4| two lines                 |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {10:[Preview]                     }|
      :%s/tw^                        |
    ]])
    feed([[<C-\><C-N>]])  -- Cancel the :substitute command.
    eq(0, eval("&modified"))
  end)

  it('shows split window when typing the pattern', function()
    feed(":%s/tw")
    screen:expect([[
      Inc substitution on           |
      two lines                     |
                                    |
      {15:~                             }|
      {15:~                             }|
      {11:[No Name] [+]                 }|
      |2| two lines                 |
      |4| two lines                 |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {10:[Preview]                     }|
      :%s/tw^                        |
    ]])
  end)

  it('shows preview with empty replacement', function()
    feed(":%s/tw/")
    screen:expect([[
      Inc substitution on           |
      o lines                       |
                                    |
      {15:~                             }|
      {15:~                             }|
      {11:[No Name] [+]                 }|
      |2| o lines                   |
      |4| o lines                   |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {10:[Preview]                     }|
      :%s/tw/^                       |
    ]])

    feed("x")
    screen:expect([[
      Inc substitution on           |
      xo lines                      |
                                    |
      {15:~                             }|
      {15:~                             }|
      {11:[No Name] [+]                 }|
      |2| {12:x}o lines                  |
      |4| {12:x}o lines                  |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {10:[Preview]                     }|
      :%s/tw/x^                      |
    ]])

    feed("<bs>")
    screen:expect([[
      Inc substitution on           |
      o lines                       |
                                    |
      {15:~                             }|
      {15:~                             }|
      {11:[No Name] [+]                 }|
      |2| o lines                   |
      |4| o lines                   |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {10:[Preview]                     }|
      :%s/tw/^                       |
    ]])

  end)

  it('shows split window when typing replacement', function()
    feed(":%s/tw/XX")
    screen:expect([[
      Inc substitution on           |
      XXo lines                     |
                                    |
      {15:~                             }|
      {15:~                             }|
      {11:[No Name] [+]                 }|
      |2| {12:XX}o lines                 |
      |4| {12:XX}o lines                 |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {10:[Preview]                     }|
      :%s/tw/XX^                     |
    ]])
  end)

  it('does not show split window for :s/', function()
    feed("2gg")
    feed(":s/tw")
    screen:sleep(1)
    screen:expect([[
      Inc substitution on           |
      two lines                     |
      Inc substitution on           |
      two lines                     |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      :s/tw^                         |
    ]])
  end)

  it("'hlsearch' is active, 'cursorline' is not", function()
    feed_command("set hlsearch cursorline")
    feed("gg")

    -- Assert that 'cursorline' is active.
    screen:expect([[
      {16:^Inc substitution on           }|
      two lines                     |
      Inc substitution on           |
      two lines                     |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      :set hlsearch cursorline      |
    ]])

    feed(":%s/tw")
    -- 'cursorline' is NOT active during preview.
    screen:expect([[
      Inc substitution on           |
      {9:tw}o lines                     |
      Inc substitution on           |
      {9:tw}o lines                     |
                                    |
      {11:[No Name] [+]                 }|
      |2| {9:tw}o lines                 |
      |4| {9:tw}o lines                 |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {10:[Preview]                     }|
      :%s/tw^                        |
    ]])
  end)

  it('highlights the replacement text', function()
    feed('ggO')
    feed('M     M       M<esc>')
    feed(':%s/M/123/g')
    screen:expect([[
      123     123       123         |
      Inc substitution on           |
      two lines                     |
      Inc substitution on           |
      two lines                     |
      {11:[No Name] [+]                 }|
      |1| {12:123}     {12:123}       {12:123}     |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {10:[Preview]                     }|
      :%s/M/123/g^                   |
    ]])
  end)

  it('actually replaces text', function()
    feed(":%s/tw/XX/g<Enter>")

    screen:expect([[
      Inc substitution on           |
      XXo lines                     |
      Inc substitution on           |
      ^XXo lines                     |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      :%s/tw/XX/g                   |
    ]])
  end)

  it('shows correct line numbers with many lines', function()
    feed("gg")
    feed("2yy")
    feed("2000p")
    feed_command("1,1000s/tw/BB/g")

    feed(":%s/tw/X")
    screen:expect([[
      BBo lines                     |
      Inc substitution on           |
      Xo lines                      |
      Inc substitution on           |
      Xo lines                      |
      {11:[No Name] [+]                 }|
      |1001| {12:X}o lines               |
      |1003| {12:X}o lines               |
      |1005| {12:X}o lines               |
      |1007| {12:X}o lines               |
      |1009| {12:X}o lines               |
      |1011| {12:X}o lines               |
      |1013| {12:X}o lines               |
      {10:[Preview]                     }|
      :%s/tw/X^                      |
    ]])
  end)

  it('does not spam the buffer numbers', function()
    -- The preview buffer is re-used (unless user deleted it), so buffer numbers
    -- will not increase on each keystroke.
    feed(":%s/tw/Xo/g")
    -- Delete and re-type the g a few times.
    feed("<BS>")
    wait()
    feed("g")
    wait()
    feed("<BS>")
    wait()
    feed("g")
    wait()
    feed("<CR>")
    wait()
    feed(":vs tmp<enter>")
    eq(3, helpers.call('bufnr', '$'))
  end)

  it('works with the n flag', function()
    feed(":%s/tw/Mix/n<Enter>")
    screen:expect([[
      Inc substitution on           |
      two lines                     |
      Inc substitution on           |
      two lines                     |
      ^                              |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      2 matches on 2 lines          |
    ]])
  end)

  it("deactivates if 'redrawtime' is exceeded #5602", function()
    -- Assert that 'inccommand' is ENABLED initially.
    eq("split", eval("&inccommand"))
    -- Set 'redrawtime' to minimal value, to ensure timeout is triggered.
    feed_command("set redrawtime=1 nowrap")
    -- Load a big file.
    feed_command("silent edit! test/functional/fixtures/bigfile_oneline.txt")
    -- Start :substitute with a slow pattern.
    feed([[:%s/B.*N/x]])
    wait()

    -- Assert that 'inccommand' is DISABLED in cmdline mode.
    eq("", eval("&inccommand"))
    -- Assert that preview cleared (or never manifested).
    screen:expect([[
      0000;<control>;Cc;0;BN;;;;;N;N|
      2F923;CJK COMPATIBILITY IDEOGR|
      2F924;CJK COMPATIBILITY IDEOGR|
      2F925;CJK COMPATIBILITY IDEOGR|
      2F926;CJK COMPATIBILITY IDEOGR|
      2F927;CJK COMPATIBILITY IDEOGR|
      2F928;CJK COMPATIBILITY IDEOGR|
      2F929;CJK COMPATIBILITY IDEOGR|
      2F92A;CJK COMPATIBILITY IDEOGR|
      2F92B;CJK COMPATIBILITY IDEOGR|
      2F92C;CJK COMPATIBILITY IDEOGR|
      2F92D;CJK COMPATIBILITY IDEOGR|
      2F92E;CJK COMPATIBILITY IDEOGR|
      2F92F;CJK COMPATIBILITY IDEOGR|
      :%s/B.*N/x^                    |
    ]])

    -- Assert that 'inccommand' is again ENABLED after leaving cmdline mode.
    feed([[<C-\><C-N>]])
    eq("split", eval("&inccommand"))
  end)

  it("clears preview if non-previewable command is edited #5585", function()
    -- Put a non-previewable command in history.
    feed_command("echo 'foo'")
    -- Start an incomplete :substitute command.
    feed(":1,2s/t/X")

    screen:expect([[
      Inc subsXitution on           |
      Xwo lines                     |
      Inc substitution on           |
      two lines                     |
                                    |
      {11:[No Name] [+]                 }|
      |1| Inc subs{12:X}itution on       |
      |2| {12:X}wo lines                 |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {10:[Preview]                     }|
      :1,2s/t/X^                     |
    ]])

    -- Select the previous command.
    feed("<C-P>")
    -- Assert that preview was cleared.
    screen:expect([[
      Inc substitution on           |
      two lines                     |
      Inc substitution on           |
      two lines                     |
                                    |
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      {15:~                             }|
      :echo 'foo'^                   |
    ]])
  end)

end)

describe("inccommand=nosplit", function()
  if helpers.pending_win32(pending) then return end

  local screen = Screen.new(20,10)

  before_each(function()
    clear()
    common_setup(screen, "nosplit", default_text .. default_text)
  end)

  after_each(function()
    if screen then screen:detach() end
  end)

  it("works with :smagic, :snomagic", function()
    feed_command("set hlsearch")
    insert("Line *.3.* here")

    feed(":%smagic/3.*/X")    -- start :smagic command
    screen:expect([[
      Inc substitution on |
      two lines           |
      Inc substitution on |
      two lines           |
      Line *.X            |
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      :%smagic/3.*/X^      |
    ]])


    feed([[<C-\><C-N>]])      -- cancel
    feed(":%snomagic/3.*/X")  -- start :snomagic command
    screen:expect([[
      Inc substitution on |
      two lines           |
      Inc substitution on |
      two lines           |
      Line *.X here       |
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      :%snomagic/3.*/X^    |
    ]])
  end)

  it('never shows preview buffer', function()
    feed_command("set hlsearch")

    feed(":%s/tw")
    screen:expect([[
      Inc substitution on |
      {9:tw}o lines           |
      Inc substitution on |
      {9:tw}o lines           |
                          |
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      :%s/tw^              |
    ]])

    feed("/BM")
    screen:expect([[
      Inc substitution on |
      BMo lines           |
      Inc substitution on |
      BMo lines           |
                          |
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      :%s/tw/BM^           |
    ]])

    feed("/")
    screen:expect([[
      Inc substitution on |
      BMo lines           |
      Inc substitution on |
      BMo lines           |
                          |
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      :%s/tw/BM/^          |
    ]])

    feed("<enter>")
    screen:expect([[
      Inc substitution on |
      BMo lines           |
      Inc substitution on |
      ^BMo lines           |
                          |
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      :%s/tw/BM/          |
    ]])
  end)

  it("clears preview if non-previewable command is edited", function()
    -- Put a non-previewable command in history.
    feed_command("echo 'foo'")
    -- Start an incomplete :substitute command.
    feed(":1,2s/t/X")

    screen:expect([[
      Inc subsXitution on |
      Xwo lines           |
      Inc substitution on |
      two lines           |
                          |
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      :1,2s/t/X^           |
    ]])

    -- Select the previous command.
    feed("<C-P>")
    -- Assert that preview was cleared.
    screen:expect([[
      Inc substitution on |
      two lines           |
      Inc substitution on |
      two lines           |
                          |
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      {15:~                   }|
      :echo 'foo'^         |
    ]])
  end)
end)

describe(":substitute, 'inccommand' with a failing expression", function()
  if helpers.pending_win32(pending) then return end

  local screen = Screen.new(20,10)
  local cases = { "", "split", "nosplit" }

  local function refresh(case)
    clear()
    common_setup(screen, case, default_text)
  end

  it('in the pattern does nothing', function()
    for _, case in pairs(cases) do
      refresh(case)
      feed_command("set inccommand=" .. case)
      feed(":silent! %s/tw\\(/LARD/<enter>")
      expect(default_text)
    end
  end)

  it('in the replacement deletes the matches', function()
    for _, case in pairs(cases) do
      refresh(case)
      local replacements = { "\\='LARD", "\\=xx_novar__xx" }

      for _, repl in pairs(replacements) do
        feed_command("set inccommand=" .. case)
        feed(":silent! %s/tw/" .. repl .. "/<enter>")
        expect(default_text:gsub("tw", ""))
        feed_command("undo")
      end
    end
  end)

  it('in the range does not error #5912', function()
    for _, case in pairs(cases) do
      refresh(case)
      feed(':100s/')

      screen:expect([[
        Inc substitution on |
        two lines           |
                            |
        {15:~                   }|
        {15:~                   }|
        {15:~                   }|
        {15:~                   }|
        {15:~                   }|
        {15:~                   }|
        :100s/^              |
      ]])

      feed('<enter>')
      screen:expect([[
        Inc substitution on |
        two lines           |
        ^                    |
        {15:~                   }|
        {15:~                   }|
        {15:~                   }|
        {15:~                   }|
        {15:~                   }|
        {15:~                   }|
        {14:E16: Invalid range}  |
      ]])
    end
  end)

end)

describe("'inccommand' and :cnoremap", function()
  local cases = { "",  "split", "nosplit" }

  local function refresh(case)
    clear()
    common_setup(nil, case, default_text)
  end

  it('work with remapped characters', function()
    for _, case in pairs(cases) do
      refresh(case)
      local cmd = "%s/lines/LINES/g"

      for i = 1, string.len(cmd) do
        local c = string.sub(cmd, i, i)
        feed_command("cnoremap ".. c .. " " .. c)
      end

      feed_command(cmd)
      expect([[
        Inc substitution on
        two LINES
        ]])
      end
  end)

  it('work when mappings move the cursor', function()
    for _, case in pairs(cases) do
      refresh(case)
      feed_command("cnoremap ,S LINES/<left><left><left><left><left><left>")

      feed(":%s/lines/,Sor three <enter>")
      expect([[
        Inc substitution on
        two or three LINES
        ]])

      feed_command("cnoremap ;S /X/<left><left><left>")
      feed(":%s/;SI<enter>")
      expect([[
        Xnc substitution on
        two or three LXNES
        ]])

      feed_command("cnoremap ,T //Y/<left><left><left>")
      feed(":%s,TX<enter>")
      expect([[
        Ync substitution on
        two or three LYNES
        ]])

      feed_command("cnoremap ;T s//Z/<left><left><left>")
      feed(":%;TY<enter>")
      expect([[
        Znc substitution on
        two or three LZNES
        ]])
      end
  end)

  it('does not work with a failing mapping', function()
    for _, case in pairs(cases) do
      refresh(case)
      feed_command("cnoremap <expr> x execute('bwipeout!')[-1].'x'")

      feed(":%s/tw/tox<enter>")

      -- error thrown b/c of the mapping
      neq(nil, eval('v:errmsg'):find('^E523:'))
      expect(default_text)
    end
  end)

  it('work when temporarily moving the cursor', function()
    for _, case in pairs(cases) do
      refresh(case)
      feed_command("cnoremap <expr> x cursor(1, 1)[-1].'x'")

      feed(":%s/tw/tox/g<enter>")
      expect(default_text:gsub("tw", "tox"))
    end
  end)

  it("work when a mapping disables 'inccommand'", function()
    for _, case in pairs(cases) do
      refresh(case)
      feed_command("cnoremap <expr> x execute('set inccommand=')[-1]")

      feed(":%s/tw/toxa/g<enter>")
      expect(default_text:gsub("tw", "toa"))
    end
  end)

  it('work with a complex mapping', function()
    for _, case in pairs(cases) do
      refresh(case)
      source([[cnoremap x <C-\>eextend(g:, {'fo': getcmdline()})
      \.fo<CR><C-c>:new<CR>:bw!<CR>:<C-r>=remove(g:, 'fo')<CR>x]])

      feed(":%s/tw/tox")
      feed("/<enter>")
      expect(default_text:gsub("tw", "tox"))
    end
  end)

end)

describe("'inccommand' autocommands", function()
  before_each(clear)

  -- keys are events to be tested
  -- values are arrays like
  --    { open = { 1 }, close = { 2, 3} }
  -- which would mean that during the test below the event fires for
  -- buffer 1 when opening the preview window, and for buffers 2 and 3
  -- when closing the preview window
  local eventsExpected = {
    BufAdd = {},
    BufDelete = {},
    BufEnter = {},
    BufFilePost = {},
    BufFilePre = {},
    BufHidden = {},
    BufLeave = {},
    BufNew = {},
    BufNewFile = {},
    BufRead = {},
    BufReadCmd = {},
    BufReadPre = {},
    BufUnload = {},
    BufWinEnter = {},
    BufWinLeave = {},
    BufWipeout = {},
    BufWrite = {},
    BufWriteCmd = {},
    BufWritePost = {},
    Syntax = {},
    FileType = {},
    WinEnter = {},
    WinLeave = {},
    CmdwinEnter = {},
    CmdwinLeave = {},
  }

  local function bufferlist(t)
    local s = ""
    for _, buffer in pairs(t) do
      s = s .. ", " .. tostring(buffer)
    end
    return s
  end

  -- fill the table with default values
  for event, _ in pairs(eventsExpected) do
    eventsExpected[event].open = eventsExpected[event].open or {}
    eventsExpected[event].close = eventsExpected[event].close or {}
  end

  local function register_autocmd(event)
    meths.set_var(event .. "_fired", {})
    feed_command("autocmd " .. event .. " * call add(g:" .. event .. "_fired, expand('<abuf>'))")
  end

  it('are not fired when splitting', function()
    common_setup(nil, "split", default_text)

    local eventsObserved = {}
    for event, _ in pairs(eventsExpected) do
      eventsObserved[event] = {}
      register_autocmd(event)
    end

    feed(":%s/tw")

    for event, _ in pairs(eventsExpected) do
      eventsObserved[event].open = meths.get_var(event .. "_fired")
      meths.set_var(event .. "_fired", {})
    end

    feed("/<enter>")

    for event, _ in pairs(eventsExpected) do
        eventsObserved[event].close = meths.get_var(event .. "_fired")
    end

    for event, _ in pairs(eventsExpected) do
      eq(event .. bufferlist(eventsExpected[event].open),
         event .. bufferlist(eventsObserved[event].open))
      eq(event .. bufferlist(eventsExpected[event].close),
         event .. bufferlist(eventsObserved[event].close))
    end
  end)

end)

describe("'inccommand' split windows", function()
  if helpers.pending_win32(pending) then return end

  local screen
  local function refresh()
    clear()
    screen = Screen.new(40,30)
    common_setup(screen, "split", default_text)
  end

  after_each(function()
    screen:detach()
  end)

  it('work after more splits', function()
    refresh()

    feed("gg")
    feed_command("vsplit")
    feed_command("split")
    feed(":%s/tw")
    screen:expect([[
      Inc substitution on {10:|}Inc substitution on|
      two lines           {10:|}two lines          |
                          {10:|}                   |
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {11:[No Name] [+]       }{10:|}{15:~                  }|
      Inc substitution on {10:|}{15:~                  }|
      two lines           {10:|}{15:~                  }|
                          {10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {10:[No Name] [+]        [No Name] [+]      }|
      |2| two lines                           |
                                              |
      {15:~                                       }|
      {15:~                                       }|
      {15:~                                       }|
      {15:~                                       }|
      {15:~                                       }|
      {10:[Preview]                               }|
      :%s/tw^                                  |
    ]])

    feed("<esc>")
    feed_command("only")
    feed_command("split")
    feed_command("vsplit")

    feed(":%s/tw")
    screen:expect([[
      Inc substitution on {10:|}Inc substitution on|
      two lines           {10:|}two lines          |
                          {10:|}                   |
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {15:~                   }{10:|}{15:~                  }|
      {11:[No Name] [+]        }{10:[No Name] [+]      }|
      Inc substitution on                     |
      two lines                               |
                                              |
      {15:~                                       }|
      {15:~                                       }|
      {10:[No Name] [+]                           }|
      |2| two lines                           |
                                              |
      {15:~                                       }|
      {15:~                                       }|
      {15:~                                       }|
      {15:~                                       }|
      {15:~                                       }|
      {10:[Preview]                               }|
      :%s/tw^                                  |
    ]])
  end)

  local settings = {
  "splitbelow",
  "splitright",
  "noequalalways",
  "equalalways eadirection=ver",
  "equalalways eadirection=hor",
  "equalalways eadirection=both",
  }

  it("are not affected by various settings", function()
    for _, setting in pairs(settings) do
      refresh()
      feed_command("set " .. setting)

      feed(":%s/tw")

      screen:expect([[
        Inc substitution on                     |
        two lines                               |
                                                |
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {11:[No Name] [+]                           }|
        |2| two lines                           |
                                                |
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {15:~                                       }|
        {10:[Preview]                               }|
        :%s/tw^                                  |
      ]])
    end
  end)

end)

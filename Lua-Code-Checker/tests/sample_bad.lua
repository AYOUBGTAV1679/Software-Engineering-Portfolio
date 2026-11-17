-- Test file with deliberate bugs matching real ones found in production

-- Bug 1: unchecked io.open, method call directly
local f = io.open("test.txt", "w")
f:write("hello")
f:close()

-- Bug 2: chained unchecked io.open
io.open("other.txt", "w"):write("data"):close()

-- OK: this one IS guarded, should NOT be flagged
local g = io.open("safe.txt", "r")
if g then
    g:close()
end

-- Bug 3: io.popen usage
local p = io.popen("dir /b")

-- Bug 4: unbounded while loop with no wait() - matches the real production
-- pattern: a function call directly in the condition, checked fresh each
-- iteration, with nothing in the body that provably changes its answer.
while not hasModelLoaded(someId) do
end

-- OK: bounded for loop with wait - should not warn (has wait)
for i = 1, 10 do
    wait(0)
end

-- Bug 5: unverified require
require("samp.events")

-- OK: known-safe require
require("moonloader")

-- Bug 6: an unrelated known name in a later namespace segment must not
-- make an unknown top-level module look trusted.
require("custom.moonloader.untrusted")

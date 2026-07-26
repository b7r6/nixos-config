-- CI entrypoint: `nvim --clean --headless -l vectors.lua` prints the 66
-- conformance vectors for checks.ono-sendai-parity (fifth column).
local dir = (arg and arg[0] and arg[0]:match("(.*)/")) or "."
local palette = dofile(dir .. "/palette.lua")
io.write(palette.emit_vectors())

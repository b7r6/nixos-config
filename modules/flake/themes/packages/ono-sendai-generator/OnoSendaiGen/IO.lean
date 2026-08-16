/-!
# File I/O utilities for Ono-Sendai theme generator
-/

namespace OnoSendaiGen

/-- Write content to a file, creating parent directories if needed -/
def writeFile (path : String) (content : String) : IO Unit := do
  -- Ensure parent directory exists
  let dir := System.FilePath.mk path |>.parent |>.getD ⟨"."⟩
  IO.FS.createDirAll dir
  -- Write the file
  IO.FS.writeFile ⟨path⟩ content
  IO.println s!"  ✓ {path}"

end OnoSendaiGen

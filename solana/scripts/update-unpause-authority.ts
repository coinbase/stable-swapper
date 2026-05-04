import { rotateRole } from "./_role-rotation";

rotateRole({
  scriptName: "update-unpause-authority.ts",
  roleLabel: "Unpause Authority",
  field: "unpauseAuthority",
  method: "updateUnpauseAuthority",
})
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

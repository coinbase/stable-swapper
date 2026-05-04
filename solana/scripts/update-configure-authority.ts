import { rotateRole } from "./_role-rotation";

rotateRole({
  scriptName: "update-configure-authority.ts",
  roleLabel: "Configure Authority",
  field: "configureAuthority",
  method: "updateConfigureAuthority",
})
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

import { rotateRole } from "./_role-rotation";

rotateRole({
  scriptName: "update-treasury-authority.ts",
  roleLabel: "Treasury Authority",
  field: "treasuryAuthority",
  method: "updateTreasuryAuthority",
})
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

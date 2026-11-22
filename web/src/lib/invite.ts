/** "ABCDE-FGHIJ", as the app shows a group's ten-letter invite code (CommunityModels.formattedInviteCode). */
export function formatInviteCode(code: string): string {
  return code.length === 10 ? `${code.slice(0, 5)}-${code.slice(5)}` : code;
}

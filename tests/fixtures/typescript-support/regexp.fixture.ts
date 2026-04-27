// basic regex
export const digits = /\d+/;
export const word = /\w+/g;

// unicode flag
export const emoji = /\p{Emoji}/u;
export const price = /\$(\d+)/gu;

// combining marks range
export const diacritics = /[̀-ͯ]/g;

// lookbehind
export const afterDollar = /(?<=\$)\d+/;

// named capture group
export const datePattern = /(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/;

export function extractDigits(input: string): string[] {
  return input.match(/\d+/g) ?? [];
}

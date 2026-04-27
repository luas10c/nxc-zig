export const digits = /\d+/;
export const combiningMarks = /[\u0300-\u036f]/g;
export const price = /\$(\d+)/gu;
export const protocol = /^http[s]?:\/\//;
export const htmlSrc = /(?<=src=")(.|\n)*?(?=")/gu;

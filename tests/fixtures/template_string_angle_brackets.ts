declare const senderName: string;
declare const senderEmail: string;

function htmlEscape(input: string): string {
  return input;
}

// Caso principal
const email1 = {
  sender: `${htmlEscape(senderName)} <${senderEmail}>`,
};

// Variacoes importantes
const email2 = `${senderName} <${senderEmail}>`;
const email3 = `Name: ${senderName}, Email: <${senderEmail}>`;
const email4 = `<${senderEmail}>`;
const email5 = `${senderName} <>`;
const email6 = `<static@email.com>`;

// Misturado com outras expressoes
const email7 = `${htmlEscape(senderName)} <${senderEmail.toLowerCase()}>`;
const email8 = `${senderName} <${senderEmail ?? "fallback@email.com"}>`;

// Template com multiplos interpolations
const email9 = `${senderName} <${senderEmail}> (${Date.now()})`;

// Edge: template vazio com brackets
const email10 = `<>`;

// Edge: so interpolation dentro de <>
const email11 = `<${senderEmail}>`;

// Edge: com optional chaining dentro do template
declare const user: { email?: string };
const email12 = `<${user?.email}>`;

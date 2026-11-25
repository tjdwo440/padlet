export class ConfigError extends Error {
  readonly variable: string;

  constructor(variable: string) {
    super(
      `${variable} 환경 변수가 없거나 형식이 올바르지 않습니다. .env.local 또는 Vercel 환경 변수 설정을 확인해 주세요.`,
    );
    this.name = "ConfigError";
    this.variable = variable;
  }
}

// 값은 절대 오류 메시지에 포함하지 않고 변수 이름만 알린다.
export function readEnv(name: string, isValid?: (value: string) => boolean) {
  const value = process.env[name]?.trim();
  if (!value || (isValid && !isValid(value))) throw new ConfigError(name);
  return value;
}

export function isHttpUrl(value: string) {
  try {
    const { protocol } = new URL(value);
    return protocol === "https:" || protocol === "http:";
  } catch {
    return false;
  }
}

export const isPublishableKey = (value: string) =>
  value.startsWith("sb_publishable_");
export const isSecretKey = (value: string) => value.startsWith("sb_secret_");

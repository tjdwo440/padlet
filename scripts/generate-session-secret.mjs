// ADMIN_SESSION_SECRET 용 무작위 문자열을 출력합니다.
import { randomBytes } from "node:crypto";

console.log(`ADMIN_SESSION_SECRET=${randomBytes(48).toString("base64url")}`);

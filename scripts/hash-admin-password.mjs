// 관리자 암호의 bcrypt 해시를 만듭니다. 암호는 화면에 표시/저장되지 않습니다.
// 사용: npm run hash-admin
import bcrypt from "bcryptjs";
import readline from "node:readline";

function askHidden(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    rl._writeToOutput = (text) => {
      if (text.includes(question)) rl.output.write(text);
    };
    rl.question(question, (answer) => {
      rl.output.write("\n");
      rl.close();
      resolve(answer);
    });
  });
}

const password = await askHidden("관리자 암호(8자 이상): ");
if (password.length < 8) {
  console.error("암호는 8자 이상이어야 합니다.");
  process.exit(1);
}

const hash = await bcrypt.hash(password, 12);
console.log("\n[Vercel 대시보드용 — 그대로 붙여넣기]");
console.log(`ADMIN_PASSWORD_HASH=${hash}`);
console.log("\n[.env.local 용 — $ 를 \\$ 로 이스케이프]");
console.log(`ADMIN_PASSWORD_HASH=${hash.replaceAll("$", "\\$")}`);

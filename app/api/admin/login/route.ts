import { adminLogin } from "@/lib/handlers";

export const runtime = "nodejs";

export async function POST(request: Request) {
  return adminLogin(request);
}

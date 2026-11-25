import { adminLogout } from "@/lib/handlers";

export const runtime = "nodejs";

export async function POST(request: Request) {
  return adminLogout(request);
}

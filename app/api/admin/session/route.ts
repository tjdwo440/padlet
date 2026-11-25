import { adminSessionStatus } from "@/lib/handlers";

export const runtime = "nodejs";

export async function GET() {
  return adminSessionStatus();
}

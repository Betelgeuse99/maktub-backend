const crypto = require("crypto");

const SB_URL = process.env.SUPABASE_URL || "https://zmolotveyvkplfrgrqqw.supabase.co";
const SB_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const [, , name, slug, pricesArg] = process.argv;
if (!name || !slug) {
  console.error("Usage: SUPABASE_SERVICE_ROLE_KEY=... node tools/add-network.js \"Maktub 3\" maktub-3");
  process.exit(1);
}
if (!SB_KEY) {
  console.error("SUPABASE_SERVICE_ROLE_KEY is required");
  process.exit(1);
}

let prices = { "24hr": 200, "7d": 800, "30d": 3000 };
if (pricesArg) {
  try { prices = JSON.parse(pricesArg); } catch (_) {
    console.error("prices must be JSON, e.g. '{\"24hr\":200,\"7d\":800,\"30d\":3000}'");
    process.exit(1);
  }
}

const key = crypto.randomBytes(32).toString("hex");
const hash = crypto.createHash("sha256").update(key).digest("hex");

(async () => {
  const res = await fetch(`${SB_URL}/rest/v1/networks`, {
    method: "POST",
    headers: {
      apikey: SB_KEY,
      Authorization: `Bearer ${SB_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: JSON.stringify({
      name,
      slug,
      api_key_hash: hash,
      plan_prices: prices,
    }),
  });
  const body = await res.text();
  if (!res.ok) {
    console.error("Failed: " + body);
    process.exit(1);
  }
  console.log("Network created: " + name + " (" + slug + ")");
  console.log("API key (shown once, store it safely):");
  console.log(key);
  console.log("\nInstall mikrotik/maktub-sync.rsc + maktub-licence.rsc on that router with this key.");
  console.log("The dashboard card appears immediately; billing is count x N5,000 on the 10th.");
})();

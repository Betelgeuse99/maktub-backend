# =====================================================================
# Maktub — licence enforcement (no grace period)
# ---------------------------------------------------------------------
# Polls the licence endpoint once a minute. If the owner's subscription
# is due, the hotspot server is disabled -> all users are locked out.
# When the licence is paid, it is enabled again.
#
# FAIL-OPEN on network errors: a cloud outage never locks the network.
# Only an explicit "active":false from the server locks it.
#
# INSTALL (per router):
#   1. Edit apiKey and hotspotServer below.
#   2. Save as script "maktub-licence" and run once.
#   3. /system scheduler add name=maktub-licence interval=1m \
#        on-event="/system script run maktub-licence"
# =====================================================================

:local apiKey "REPLACE_WITH_NETWORK_API_KEY"
:local apiUrl "https://zmolotveyvkplfrgrqqw.supabase.co/functions/v1/maktub/api/licence"
:local hotspotServer "hs-bridge-LAN"

:local answer ""
:do {
    /tool fetch url=$apiUrl mode=https check-certificate=no \
        http-header-field="x-api-key:$apiKey" dst-path=maktub-lic.txt
    :set answer [/file get maktub-lic.txt contents]
    /file remove maktub-lic.txt
} on-error={
    :log warning "MAKTUB-LIC: fetch failed - leaving hotspot as is (fail-open)"
    :return ""
}

:local isActive false
:if ([:typeof [:find $answer "\"active\":true"]] != "nil") do={ :set isActive true }
:if ([:typeof [:find $answer "\"active\":false"]] != "nil") do={ :set isActive false }

:local hs [/ip hotspot find name=$hotspotServer]
:if ([:len $hs] = 0) do={
    :log error "MAKTUB-LIC: hotspot server not found: $hotspotServer"
    :return ""
}
:local disabled [/ip hotspot get $hs disabled]

:if (($isActive = false) and ($disabled = false)) do={
    /ip hotspot disable $hs
    :log warning "MAKTUB-LIC: subscription due - hotspot disabled, all users locked out"
}
:if (($isActive = true) and ($disabled = true)) do={
    /ip hotspot enable $hs
    :log warning "MAKTUB-LIC: subscription active - hotspot enabled"
}

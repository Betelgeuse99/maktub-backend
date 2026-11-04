# =====================================================================
# Maktub — router -> dashboard sync
# ---------------------------------------------------------------------
# Sends every hotspot user + the active-session list to the dashboard.
# Only outbound HTTPS is needed. No inbound access, no VPN.
#
# INSTALL (per router):
#   1. Edit apiKey below with THAT network's key.
#   2. /system script add name=maktub-sync source=[/file get maktub-sync.rsc contents]
#      (or paste the body into a script named maktub-sync)
#   3. /system script run maktub-sync
#   4. /system scheduler add name=maktub-sync interval=2m \
#        on-event="/system script run maktub-sync"
# =====================================================================

:local apiKey "REPLACE_WITH_NETWORK_API_KEY"
:local apiUrl "https://zmolotveyvkplfrgrqqw.supabase.co/functions/v1/maktub/api/mikhmon-sync"

:local out ""
:foreach i in=[/ip hotspot user find] do={
    :local name [/ip hotspot user get $i name]
    :local pass [/ip hotspot user get $i password]
    :local prof [/ip hotspot user get $i profile]
    :local mac  [/ip hotspot user get $i mac-address]
    :local dis  [/ip hotspot user get $i disabled]
    :local lim  [/ip hotspot user get $i limit-uptime]
    :local up   [/ip hotspot user get $i uptime]
    :local com  [/ip hotspot user get $i comment]
    :set out ($out . "U|" . $name . "|" . $pass . "|" . $prof . "|" . $mac . "|" . $dis . "|" . $lim . "|" . $up . "|" . $com . "\n")
}
:foreach a in=[/ip hotspot active find] do={
    :local au [/ip hotspot active get $a user]
    :if ([:len $au] > 0) do={
        :set out ($out . "A|" . $au . "\n")
    }
}
:set out ($out . "F|1\n")

:do {
    /tool fetch url=$apiUrl mode=https check-certificate=no http-method=post \
        http-header-field="Content-Type:text/plain,x-api-key:$apiKey" \
        http-data=$out keep-result=no
} on-error={
    :log warning "MAKTUB-SYNC: upload failed (will retry)"
}

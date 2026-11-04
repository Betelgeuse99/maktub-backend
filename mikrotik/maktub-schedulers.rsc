# Maktub — schedulers
# Run once per router after installing maktub-sync and maktub-licence.

/system scheduler remove [find name="maktub-sync"]
/system scheduler remove [find name="maktub-licence"]

/system scheduler add name=maktub-sync interval=2m on-event="/system script run maktub-sync" comment="Maktub dashboard sync"
/system scheduler add name=maktub-licence interval=1m on-event="/system script run maktub-licence" comment="Maktub licence lock"

/system scheduler print where name~"maktub"

nftables:
  config:
    tables:
      inet:
        filter:
          chains:
            input:
              type: filter hook input priority 0
              policy: drop
              rules:
                - ct state established,related accept
                - ct state invalid drop
                - iif lo accept
                # Allow all ICMP and IGMP traffic, but enforce a rate limit
                # to help prevent some types of flood attacks.
                - ip protocol icmp limit rate 4/second accept
                - ip6 nexthdr ipv6-icmp limit rate 4/second accept
                - ip protocol igmp limit rate 4/second accept
            outgoing:
              type: filter hook output priority 0
              policy: accept
            forward:
                type: filter hook forward priority 0
                policy: drop;
                rules:
                  - ct state established,related accept
                  # Drop invalid packets.
                  - ct state invalid drop
      ip:
        nat:
          chains:
            postrouting:
              type: nat hook postrouting priority 100
              policy: accept
      ip6:
        nat:
          chains:
            postrouting:
              type: nat hook postrouting priority 100
              policy: accept
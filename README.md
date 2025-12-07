# A very thin wrapper to saltify nftables

## What can the formula do?

This is a wrapper around [nftables-service][0]

## installation

Just add the hook it up like every other formula and do the needed

### Required salt master config:

```
file_roots:
  base:
    [ snip ]
    - {{ formulas_base_dir }}/madeyougoaway/salt/

pillar_roots:
  base:
    [ snip ]
    - {{ formulas_base_dir }}/madeyougoaway/pillar/
```

## cfgmgmt-template integration

if you are using our [cfgmgmt-template](https://github.com/darix/cfgmgmt-template) as a starting point the saltmaster you can simplify the setup with:

```
git submodule add https://github.com/darix/madeyougoaway formulas/madeyougoaway
ln -s /srv/cfgmgmt/formulas/madeyougoaway/config/enable_madeyougoaway.conf /etc/salt/master.d/
systemctl restart saltmaster
```

## How to use

Follow pillar.example for your pillar settings.
In your salt machine configuration include `madeyougoaway.forgejo` and/or
`madeyougoaway.forgejo-runner`.

## License

[AGPL-3.0-only](https://spdx.org/licenses/AGPL-3.0-only.html)

[0]: https://build.opensuse.org/package/show/home:darix:apps/nftables-service
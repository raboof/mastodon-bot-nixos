{ config, pkgs, lib, ... }:

let
  mastodon-bot =
    ((pkgs.callPackage ./. { }).package.overrideAttrs (old: { 
      buildInputs = old.buildInputs ++ [ pkgs.lumo ];
      postInstall = ''
        patchShebangs $out/bin/mastodon-bot
      '';
    }));
  mastodon-bot-compiled = pkgs.stdenv.mkDerivation {
    name = "mastodon-bot-compiled";
    unpackPhase = "true";
    buildInputs = [ pkgs.lumo ];
    buildPhase = ''
      # where should the output go? I guess we can't write?
      cp -r ${mastodon-bot}/lib/node_modules/mastodon-bot/* .
      chmod -R a+w *
      cat > build.cljs <<EOF;
      (require '[lumo.build.api :as b])

(b/build "mastodon_bot"
  {:main 'mastodon-bot.core
   :output-to "out/mastodon-bot.js"
   :target :nodejs
   })

EOF

      lumo -c mastodon_bot build.cljs
      rm out/mastodon_bot/*.cljs
    '';
    installPhase = ''
      mkdir -p $out/lib
      cp -r out $out/lib

      # We're copying the node_modules so we don't need a dependency on the 'fat' mastodon-bot
      cp -r node_modules $out/lib

      mkdir -p $out/bin
      cat > $out/bin/mastodon-bot <<EOF;
      #!/bin/sh
      cd $out/lib
      NODE_PATH=$out/lib/node_modules ${pkgs.nodejs}/bin/node out/mastodon-bot.js &>/tmp/logs
EOF

      chmod a+x $out/bin/mastodon-bot
    '';
  };
  mastodon-bot-hack42 = pkgs.symlinkJoin {
    name = "mastodon-bot-hack42";
    paths = [ mastodon-bot-compiled ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = "wrapProgram $out/bin/mastodon-bot --set MASTODON_BOT_CONFIG ${./config.hack42.edn}";
  };
in
{
  systemd.targets."posted" = {};

  systemd.services."hack42-mastodon-bot" = {
    description = "mastodon-bot with the hack42 configuration";

    requires = [ "network-online.target" ];
    after = [ "network-online.target" ];

    requiredBy = [ "posted.target" ];

    unitConfig = {
      DefaultDependencies = false;
    };

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      # To give DNS time to actually initialize :/
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
      ExecStart = "${mastodon-bot-hack42}/bin/mastodon-bot";
      # And wind down after running
      ExecStop = "${pkgs.systemd}/bin/shutdown -h";
    };
  };

  systemd.defaultUnit = "posted.target";
}

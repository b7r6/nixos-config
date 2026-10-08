{ config, pkgs, ... }:

{
  systemd.services.vertex-shim = {
    description = "Vertex-to-OpenRouter Shim [Opencode Integrated]";
    wantedBy = [ "multi-user.target" ];
    
    # Add the missing python dependencies to the system path for this service
    path = with pkgs; [ 
      bc 
      jq 
      curl 
      (python311.withPackages (ps: with ps; [ 
        litellm 
        backoff 
        orjson 
        uvicorn 
        fastapi 
      ]))
    ];

    serviceConfig = {
      # Use the .envrc found in your fxy-src
      ExecStartPre = pkgs.writeShellScript "audit" ''
        set -euo pipefail
        # Direct source the envrc
        source /home/justin/src/fxy/.envrc
        
        echo ">>> Auditing OpenRouter Pricing..."
        METADATA=$(curl -s https://openrouter.ai/api/v1/models)
        PRICE=$(echo "$METADATA" | jq -r '.data[] | select(.id == "google/gemini-3-pro-preview") | .pricing.prompt // 999')
        
        if (( $(echo "$PRICE > 0.00000205" | bc -l) )); then
          echo "PRICE TOO HIGH: $PRICE"
          exit 1
        fi
      '';

      ExecStart = pkgs.writeShellScript "start-shim" ''
        set -euo pipefail
        source /home/justin/src/fxy/.envrc
        # Execute via the litellm in our path
        litellm --port 8080
      '';
      
      User = "root";
      Restart = "on-failure";
      RestartSec = "5s";
      WorkingDirectory = "/home/justin/src/fxy";
    };
  };
}

locals {
  vin_moe_cluster_issuer       = "letsencrypt-prod-vin-moe"
  vinnel_cloud_cluster_issuer  = "letsencrypt-prod-vinnel-cloud"
  monke_academy_cluster_issuer = "letsencrypt-prod-monke-academy"

  authelia_forward_auth_annotations = {
    "nginx.ingress.kubernetes.io/auth-url"              = "http://authelia.services.svc.cluster.local/api/authz/auth-request"
    "nginx.ingress.kubernetes.io/auth-signin"           = "https://auth.vinnel.cloud/?rd=$scheme://$http_host$request_uri"
    "nginx.ingress.kubernetes.io/auth-response-headers" = "Remote-User,Remote-Groups,Remote-Name,Remote-Email"
  }

  admin_frame_brand_css = <<-EOT
    :root{color-scheme:light dark;
      --bg:light-dark(#faf8f5,#0c0c0d);
      --fg:light-dark(#2a2825,#cececa);
      --muted:light-dark(#4a4743,#a9a9a3);
      --dim:light-dark(#625e57,#74746f);
      --accent:light-dark(#b3466b,#f7b9d1);
      --accent-strong:light-dark(#8f3355,#fbd3e2);}
    *{font-family:'JetBrains Mono',ui-monospace,'SF Mono',Menlo,Consolas,'Liberation Mono',monospace !important;}
    html,body,#root,#app,#__next{background:var(--bg) !important;color:var(--fg) !important;}
    a{color:var(--accent) !important;}
    a:hover{color:var(--accent-strong) !important;}
    :root[data-vinnel-theme=light]{color-scheme:light;}
    :root[data-vinnel-theme=dark]{color-scheme:dark;}
  EOT

  admin_frame_theme_js_app = {
    adguard  = "localStorage.setItem('account_theme',t);"
    signoz   = "localStorage.setItem('THEME',t);localStorage.setItem('THEME_AUTO_SWITCH','false');"
    registry = "localStorage.setItem('styleModeLocal',d?'DARK':'LIGHT');"
  }

  admin_frame_theme_js = {
    for slug in concat(local.admin_frame_css_slugs, ["registry"]) : slug => join("", [
      "(function(){var m=document.cookie.match(/(?:^|; )theme=(dark|light)/);if(!m)return;var t=m[1],d=t==='dark';",
      "try{document.documentElement.setAttribute('data-vinnel-theme',t);}catch(e){}",
      "try{var q=window.matchMedia.bind(window);window.matchMedia=function(s){",
      "if(/prefers-color-scheme/.test(s)){var w=/dark/.test(s)?d:!d;",
      "return{media:s,matches:w,onchange:null,addListener:function(){},removeListener:function(){},",
      "addEventListener:function(){},removeEventListener:function(){},dispatchEvent:function(){return false;}};}",
      "return q(s);};}catch(e){}",
      "try{${lookup(local.admin_frame_theme_js_app, slug, "")}}catch(e){}",
      "})();",
    ])
  }

  admin_frame_brand_locations = {
    for slug in concat(local.admin_frame_css_slugs, ["registry"]) : slug => <<-EOT
      location = /__vinnel-brand.css {
        default_type text/css;
        expires 1h;
        return 200 "${local.admin_frame_brand_css}";
      }
      location = /__vinnel-brand.js {
        default_type application/javascript;
        expires 1h;
        return 200 "${local.admin_frame_theme_js[slug]}";
      }
    EOT
  }

  admin_frame_css_slugs = ["adguard", "signoz", "hubble", "proxy", "velero", "seaweed"]

  admin_framed_annotations = {
    for slug in ["adguard", "signoz", "hubble", "shell", "proxy", "velero", "seaweed", "cloud"] : slug => merge(
      {
        "nginx.ingress.kubernetes.io/configuration-snippet" = join("\n", compact([
          "more_clear_headers \"X-Frame-Options\";",
          "more_clear_headers \"Content-Security-Policy\";",
          "if ($http_sec_fetch_dest = \"document\") {",
          "  return 302 https://admin.vinnel.cloud/#${slug};",
          "}",
          contains(local.admin_frame_css_slugs, slug) ? join("\n", [
            "proxy_set_header Accept-Encoding \"\";",
            "sub_filter '</head>' '<script src=\"/__vinnel-brand.js\"></script><link rel=\"stylesheet\" href=\"/__vinnel-brand.css\" /></head>';",
            "sub_filter_once on;",
          ]) : "",
        ]))
      },
      contains(local.admin_frame_css_slugs, slug) ? {
        "nginx.ingress.kubernetes.io/server-snippet" = local.admin_frame_brand_locations[slug]
      } : {}
    )
  }

  admin_framed_service_annotations = {
    for slug, ann in local.admin_framed_annotations :
    slug => merge(local.authelia_forward_auth_annotations, ann)
  }
}
locals {
  images = jsondecode(file("${path.module}/images.json"))
}

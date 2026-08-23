locals {
  vin_moe_cluster_issuer       = "letsencrypt-prod-vin-moe"
  vinnel_cloud_cluster_issuer  = "letsencrypt-prod-vinnel-cloud"
  monke_academy_cluster_issuer = "letsencrypt-prod-monke-academy"

  authelia_forward_auth_annotations = {
    "nginx.ingress.kubernetes.io/auth-url"              = "http://authelia.${kubernetes_namespace_v1.auth.metadata[0].name}.svc.cluster.local/api/authz/auth-request"
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
    adguard = "localStorage.setItem('account_theme',t);"
    signoz  = "localStorage.setItem('THEME',t);localStorage.setItem('THEME_AUTO_SWITCH','false');"
  }

  admin_frame_theme_js = {
    for slug in local.admin_frame_css_slugs : slug => join("", [
      "(function(){var t=null,d=false,ls=[],qs=[];",
      "try{var q=window.matchMedia.bind(window);window.matchMedia=function(s){",
      "if(t===null||!/prefers-color-scheme/.test(s))return q(s);",
      "var w=/dark/.test(s),o={media:s,matches:w===d,onchange:null,",
      "addListener:function(f){ls.push([o,f]);},",
      "removeListener:function(f){ls=ls.filter(function(x){return x[1]!==f;});},",
      "addEventListener:function(e,f){if(e==='change')ls.push([o,f]);},",
      "removeEventListener:function(e,f){ls=ls.filter(function(x){return x[1]!==f;});},",
      "dispatchEvent:function(){return false;}};qs.push([o,w]);return o;};}catch(e){}",
      "function ev(o){return{type:'change',media:o.media,matches:o.matches};}",
      "function a(v){t=v;d=v==='dark';",
      "try{document.documentElement.setAttribute('data-vinnel-theme',v);}catch(e){}",
      "try{${lookup(local.admin_frame_theme_js_app, slug, "")}}catch(e){}",
      "qs.forEach(function(x){x[0].matches=x[1]===d;",
      "if(x[0].onchange)try{x[0].onchange.call(x[0],ev(x[0]));}catch(e){}});",
      "ls.forEach(function(x){try{x[1].call(x[0],ev(x[0]));}catch(e){}});}",
      "var m=document.cookie.match(/(?:^|; )theme=(dark|light)/);if(m)a(m[1]);",
      "addEventListener('message',function(e){if(e.origin!=='https://admin.vinnel.cloud')return;",
      "var v=e.data&&e.data.vinnelTheme;if(v!==t&&(v==='dark'||v==='light')){a(v);",
      "${contains(keys(local.admin_frame_theme_js_app), slug) ? "location.reload();" : ""}}});",
      "})();",
    ])
  }

  admin_frame_css_href = "/__vinnel-brand.${substr(sha1(local.admin_frame_brand_css), 0, 8)}.css"

  admin_frame_js_href = {
    for slug, js in local.admin_frame_theme_js : slug => "/__vinnel-brand.${substr(sha1(js), 0, 8)}.js"
  }

  admin_frame_brand_locations = {
    for slug in local.admin_frame_css_slugs : slug => <<-EOT
      location = ${local.admin_frame_css_href} {
        default_type text/css;
        expires max;
        return 200 "${local.admin_frame_brand_css}";
      }
      location = ${local.admin_frame_js_href[slug]} {
        default_type application/javascript;
        expires max;
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
            "sub_filter '</head>' '<script src=\"${local.admin_frame_js_href[slug]}\"></script><link rel=\"stylesheet\" href=\"${local.admin_frame_css_href}\" /></head>';",
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

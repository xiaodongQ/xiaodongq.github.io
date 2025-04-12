# 在所有 post 末尾附上新窗链接脚本
Jekyll::Hooks.register :posts, :pre_render do |post|
  post.content = post.content + "\n\n<script src=\"#{post.site.baseurl}/assets/js/define-link-target-blank.js\"></script>\n"
end

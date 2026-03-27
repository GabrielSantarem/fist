import lustre/attribute
import lustre/element
import lustre/element/html

pub fn view(title: String) {
  html.html([], [
    html.head([], [
      html.title([], title),
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width, initial-scale=1"),
      ]),
    ]),
    html.body(
      [attribute.styles([#("font-family", "sans-serif"), #("padding", "2rem")])],
      [
        html.h1([], [element.text("Fist + Lustre SSR 👊")]),
        html.p([], [
          element.text(
            "Esta página foi renderizada no servidor usando o seu router!",
          ),
        ]),
        html.div(
          [
            attribute.styles([
              #("background", "#eee"),
              #("padding", "1rem"),
              #("border-radius", "8px"),
            ]),
          ],
          [element.text("Conteúdo dinâmico: " <> title)],
        ),
      ],
    ),
  ])
}

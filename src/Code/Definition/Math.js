const katex = require("katex");

class MathElement extends HTMLElement {
  static get properties() {
    return {
      displayMode: { type: Boolean },
      exp: { type: String },
    };
  }
  constructor() {
    super();
    this.displayMode = false;
    this.exp = "a=b";
  }
  
  const element = elementRef.attachShadow({ mode: "open" });
  const wrapper = document.createElement("span");
  
  render () {
    katex.render(exp, span, {throwOnError: false})
  }
}

customElements.define("math", MathElement);

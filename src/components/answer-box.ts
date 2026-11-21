import { Container, Markdown, Spacer } from '@mariozechner/pi-tui';
import { formatResponse } from '../utils/markdown-table.js';
import { markdownTheme, theme } from '../theme.js';

export class AnswerBoxComponent extends Container {
  private readonly body: Markdown;

  constructor(initialText = '') {
    super();
    this.addChild(new Spacer(1));
    this.body = new Markdown('', 0, 0, markdownTheme, { color: (line) => line });
    this.addChild(this.body);
    this.setText(initialText);
  }

  setText(text: string) {
    const rendered = formatResponse(text);
    // Prevent "⏺" from appearing on its own line when model output starts with newlines.
    const normalized = rendered.replace(/^\n+/, '');
    this.body.setText(`${theme.primary('⏺ ')}${normalized}`);
  }
}

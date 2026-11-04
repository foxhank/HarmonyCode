import { ToolInputError } from '../ToolErrors';

/** The result of applying one edit in memory. */
export class EditResult {
  content: string;
  count: number;

  constructor(content: string, count: number) {
    this.content = content;
    this.count = count;
  }
}

/** Exact search-and-replace with the checks and hints the edit tools share. */
export class TextEdit {
  /** Applies one replacement to `content`. Throws ToolInputError explaining what to fix. */
  static apply(content: string, oldString: string, newString: string, all: boolean, rel: string): EditResult {
    let oldStr = oldString;
    let newStr = newString;
    if (oldStr.length === 0) {
      throw new ToolInputError('old_string is empty. Use write_file to replace a whole file.');
    }
    if (oldStr === newStr) {
      throw new ToolInputError('old_string and new_string are identical; nothing to change.');
    }
    // Files with CRLF endings: models usually send LF.
    if (content.indexOf('\r\n') >= 0 && oldStr.indexOf('\r\n') < 0) {
      oldStr = oldStr.replace(new RegExp('\n', 'g'), '\r\n');
      newStr = newStr.replace(new RegExp('\n', 'g'), '\r\n');
    }
    const count = TextEdit.occurrences(content, oldStr);
    if (count === 0) {
      throw new ToolInputError(`old_string was not found in ${rel}.` + TextEdit.hint(content, oldStr));
    }
    if (count > 1 && !all) {
      throw new ToolInputError(`old_string occurs ${count} times in ${rel}. Add surrounding lines to make it ` +
        `unique, or set replace_all to true.`);
    }
    return new EditResult(content.split(oldStr).join(newStr), count);
  }

  static occurrences(text: string, needle: string): number {
    let n = 0;
    let i = text.indexOf(needle);
    while (i >= 0) {
      n++;
      i = text.indexOf(needle, i + needle.length);
    }
    return n;
  }

  /** Points the model at the likely cause when the text is there with different whitespace. */
  static hint(content: string, oldStr: string): string {
    const squash = (s: string): string => s.replace(new RegExp('\\s+', 'g'), ' ').trim();
    const firstLine = oldStr.split('\n').map((l: string) => l.trim()).find((l: string) => l.length > 0) ?? '';
    if (firstLine.length === 0) {
      return '';
    }
    const lines = content.split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].trim() === firstLine) {
        if (squash(content).indexOf(squash(oldStr)) >= 0) {
          return ` Text with different whitespace/indentation exists near line ${i + 1}; read the file and ` +
            `copy the exact text.`;
        }
        return ` The first line of old_string appears at line ${i + 1}, but the following lines differ. ` +
          `Read the file again and copy the exact text.`;
      }
    }
    return ' Read the file again and copy the exact text (without line-number prefixes).';
  }
}

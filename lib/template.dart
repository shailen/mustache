part of mustache;

final RegExp _validTag = new RegExp(r'^[0-9a-zA-Z\_\-]+$');

Template _parse(String source, {bool lenient : false}) {
	var tokens = _scan(source, lenient);
	var ast = _parseTokens(tokens, lenient);
	return new _Template(ast, lenient);
}

_Node _parseTokens(List<_Token> tokens, bool lenient) {
	var stack = new List<_Node>()..add(new _Node(_OPEN_SECTION, 'root', 0, 0));
	for (var t in tokens) {
		if (t.type == _TEXT || t.type == _VARIABLE || t.type == _UNESC_VARIABLE) {
			if (t.type == _VARIABLE || t.type == _UNESC_VARIABLE)
				_checkTagChars(t, lenient);
			stack.last.children.add(new _Node.fromToken(t));
		
		} else if (t.type == _OPEN_SECTION || t.type == _OPEN_INV_SECTION) {
			_checkTagChars(t, lenient);
			var child = new _Node.fromToken(t);
			stack.last.children.add(child);
			stack.add(child);

		} else if (t.type == _CLOSE_SECTION) {
			_checkTagChars(t, lenient);

			if (stack.last.value != t.value) {
				throw new MustacheFormatException('Mismatched tag, '
					"expected: '${stack.last.value}', "
					"was: '${t.value}', "
					'at: ${t.line}:${t.column}.', t.line, t.column);
			}

			stack.removeLast();
		
		} else if (t.type == _COMMENT) {
			// Do nothing

		} else {
			throw new UnimplementedError();
		}
	}

	return stack.last;
}

_checkTagChars(_Token t, bool lenient) {
		if (!lenient && !_validTag.hasMatch(t.value)) {
			throw new MustacheFormatException(
				'Tag contained invalid characters in name, '
				'allowed: 0-9, a-z, A-Z, underscore, and minus, '
				'at: ${t.line}:${t.column}.', t.line, t.column);
		}	
}

class _Template implements Template {
	_Template(this._root, this._lenient) {
		_htmlEscapeMap[_AMP] = '&amp;';
		_htmlEscapeMap[_LT] = '&lt;';
		_htmlEscapeMap[_GT] = '&gt;';
		_htmlEscapeMap[_QUOTE] = '&quot;';
		_htmlEscapeMap[_APOS] = '&#x27;';
		_htmlEscapeMap[_FORWARD_SLASH] = '&#x2F;';
	}

	final _Node _root;
	final List _stack = new List();
	final Map _htmlEscapeMap = new Map<int, String>();
	final bool _lenient;
	
	bool _htmlEscapeValues;
	StringSink _sink;

	String renderString(values, {bool lenient : false, bool htmlEscapeValues : true}) {
		var buf = new StringBuffer();
		render(values, buf, lenient: lenient, htmlEscapeValues: htmlEscapeValues);
		return buf.toString();
	}

	void render(values, StringSink sink, {bool lenient : false, bool htmlEscapeValues : true}) {
		_sink = sink;
		_htmlEscapeValues = htmlEscapeValues;
		_stack.clear();
		_stack.add(values);	
		_root.children.forEach(_renderNode);
		_sink = null;
	}

	_write(String output) => _sink.write(output);

	_renderNode(node) {
		switch (node.type) {
			case _TEXT:
				_renderText(node);
				break;
			case _VARIABLE:
				_renderVariable(node);
				break;
			case _UNESC_VARIABLE:
				_renderVariable(node, escape: false);
				break;
			case _OPEN_SECTION:
				_renderSection(node);
				break;
			case _OPEN_INV_SECTION:
				_renderInvSection(node);
				break;
			case _COMMENT:
				break; // Do nothing.
			default:
				throw new UnimplementedError();
		}
	}

	_renderText(node) {
		_write(node.value);
	}

	// Walks up the stack looking for the variable.
	_resolveValue(String name) {
		var map =	_stack
	              .reversed
	              .firstWhere(
	        	        (v) => v is Map && v.containsKey(name),
	        	        orElse: () => null);
	  return map != null ? map[name] : null;
	}

	_renderVariable(node, {bool escape : true}) {
		final value = _resolveValue(node.value);
		if (value == null) {
			if (!_lenient)
				throw new MustacheFormatException(
					'Value was null or missing, '
					'variable: ${node.value}, '
					'at: ${node.line}:${node.column}.', node.line, node.column);
		} else {
			var output = !escape || !_htmlEscapeValues 
				? value.toString()
				: _htmlEscape(value.toString());
			_write(output);
		}
	}

	_renderSectionWithValue(node, value) {
		_stack.add(value);
		node.children.forEach(_renderNode);
		_stack.removeLast();
	}

	_renderSection(node) {
		final value = _resolveValue(node.value);
		if (value is List) {
			value.forEach((v) => _renderSectionWithValue(node, v));
		} else if (value is Map) {
			_renderSectionWithValue(node, value);
		} else if (value == true) {
			_renderSectionWithValue(node, value);
		} else if (value == false) {
			// Do nothing.
		} else if (value == null) {
			if (!_lenient)
				throw new MustacheFormatException(
					'Value was null or missing, '
					'section: ${node.value}, '
					'at: ${node.line}:${node.column}.', node.line, node.column);
		} else {
			throw new MustacheFormatException(
				'Invalid value type for section, '
				'section: ${node.value}, '
				'type: ${value.runtimeType}, '
				'at: ${node.line}:${node.column}.', node.line, node.column);
		}
	}

	_renderInvSection(node) {
		final value = _resolveValue(node.value);
		if ((value is List && value.isEmpty) || value == false) {
			_renderSectionWithValue(node, value);
		} else if (value == true || value is Map || value is List) {
			// Do nothing.
		} else if (value == null) {
			if (_lenient) {
				_renderSectionWithValue(node, value);
			} else {
				throw new MustacheFormatException(
					'Value was null or missing, '
					'inverse-section: ${node.value}, '
					'at: ${node.line}:${node.column}.', node.line, node.column);
			}
		} else {
			throw new MustacheFormatException(
				'Invalid value type for inverse section, '
				'section: ${node.value}, '
				'type: ${value.runtimeType}, '
				'at: ${node.line}:${node.column}.', node.line, node.column);
		}
	}

	String _htmlEscape(String s) {
		var buffer = new StringBuffer();
		int startIndex = 0;
		int i = 0;
		for (int c in s.runes) {			
			if (c == _AMP
					|| c == _LT
					|| c == _GT
					|| c == _QUOTE
					|| c == _APOS
					|| c == _FORWARD_SLASH) {
				buffer.write(s.substring(startIndex, i));
				buffer.write(_htmlEscapeMap[c]);
				startIndex = i + 1;
			}
			i++;
		}
		buffer.write(s.substring(startIndex));			
		return buffer.toString();
	}
}

_visit(_Node root, visitor(_Node n)) {
	var _stack = new List<_Node>()..add(root);
	while (!_stack.isEmpty) {
		var node = _stack.removeLast();
		_stack.addAll(node.children);
		visitor(node);
	}
}

class _Node {
	_Node(this.type, this.value, this.line, this.column);
	_Node.fromToken(_Token token)
		: type = token.type,
		  value = token.value,
		  line = token.line,
		  column = token.column;
	final int type;
	final String value;
	final int line;
	final int column;
	final List<_Node> children = new List<_Node>();
	String toString() => '_Node: ${tokenTypeString(type)}';
}
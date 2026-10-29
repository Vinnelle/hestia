package tools

import (
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"
	"unicode"
)

const (
	maxExpression = 200
	maxDepth      = 64
)

type calc struct {
	in    string
	at    int
	depth int
}

func Calculate(expr string) (string, error) {
	if len(expr) > maxExpression {
		return "", fmt.Errorf("the expression is over %d characters", maxExpression)
	}
	expr = strings.NewReplacer("×", "*", "÷", "/", "−", "-", "**", "^").Replace(expr)
	c := &calc{in: expr}
	v, err := c.sum()
	if err != nil {
		return "", err
	}
	if c.skip(); c.at < len(c.in) {
		return "", fmt.Errorf("unexpected %q", c.in[c.at:])
	}
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return "", errors.New("the result isn't a finite number")
	}
	if v == math.Trunc(v) && math.Abs(v) < 1e15 {
		return strconv.FormatFloat(v, 'f', -1, 64), nil
	}
	return strconv.FormatFloat(v, 'g', 15, 64), nil
}

func (c *calc) skip() {
	for c.at < len(c.in) && unicode.IsSpace(rune(c.in[c.at])) {
		c.at++
	}
}

func (c *calc) eat(op byte) bool {
	if c.skip(); c.at < len(c.in) && c.in[c.at] == op {
		c.at++
		return true
	}
	return false
}

func (c *calc) sum() (float64, error) {
	if c.depth++; c.depth > maxDepth {
		return 0, errors.New("the expression is nested too deeply")
	}
	defer func() { c.depth-- }()
	v, err := c.product()
	for err == nil {
		switch {
		case c.eat('+'):
			var r float64
			r, err = c.product()
			v += r
		case c.eat('-'):
			var r float64
			r, err = c.product()
			v -= r
		default:
			return v, nil
		}
	}
	return 0, err
}

func (c *calc) product() (float64, error) {
	v, err := c.unary()
	for err == nil {
		var r float64
		switch {
		case c.eat('*'):
			r, err = c.unary()
			v *= r
		case c.eat('/'):
			if r, err = c.unary(); err == nil && r == 0 {
				err = errors.New("division by zero")
			}
			v /= r
		case c.eat('%'):
			if r, err = c.unary(); err == nil && r == 0 {
				err = errors.New("division by zero")
			}
			v = math.Mod(v, r)
		default:
			return v, nil
		}
	}
	return 0, err
}

func (c *calc) unary() (float64, error) {
	if c.depth++; c.depth > maxDepth {
		return 0, errors.New("the expression is nested too deeply")
	}
	defer func() { c.depth-- }()
	switch {
	case c.eat('-'):
		v, err := c.unary()
		return -v, err
	case c.eat('+'):
		return c.unary()
	}
	return c.power()
}

func (c *calc) power() (float64, error) {
	v, err := c.factorial()
	if err != nil || !c.eat('^') {
		return v, err
	}
	e, err := c.unary()
	return math.Pow(v, e), err
}

func (c *calc) factorial() (float64, error) {
	v, err := c.primary()
	for err == nil && c.eat('!') {
		if v < 0 || v != math.Trunc(v) || v > 170 {
			return 0, errors.New("factorial needs a whole number from 0 to 170")
		}
		v = math.Gamma(v + 1)
	}
	return v, err
}

var functions = map[string]func(...float64) (float64, error){
	"sqrt":  one(math.Sqrt),
	"cbrt":  one(math.Cbrt),
	"abs":   one(math.Abs),
	"ln":    one(math.Log),
	"log":   one(math.Log10),
	"log10": one(math.Log10),
	"log2":  one(math.Log2),
	"exp":   one(math.Exp),
	"sin":   one(math.Sin),
	"cos":   one(math.Cos),
	"tan":   one(math.Tan),
	"asin":  one(math.Asin),
	"acos":  one(math.Acos),
	"atan":  one(math.Atan),
	"floor": one(math.Floor),
	"ceil":  one(math.Ceil),
	"round": one(math.Round),
	"min":   many(math.Min),
	"max":   many(math.Max),
}

func one(f func(float64) float64) func(...float64) (float64, error) {
	return func(args ...float64) (float64, error) {
		if len(args) != 1 {
			return 0, errors.New("takes one number")
		}
		return f(args[0]), nil
	}
}

func many(f func(float64, float64) float64) func(...float64) (float64, error) {
	return func(args ...float64) (float64, error) {
		if len(args) == 0 {
			return 0, errors.New("takes at least one number")
		}
		v := args[0]
		for _, a := range args[1:] {
			v = f(v, a)
		}
		return v, nil
	}
}

func (c *calc) primary() (float64, error) {
	if c.eat('(') {
		v, err := c.sum()
		if err == nil && !c.eat(')') {
			err = errors.New("missing )")
		}
		return v, err
	}
	start := c.at
	if c.at < len(c.in) && unicode.IsLetter(rune(c.in[c.at])) {
		for c.at < len(c.in) && (unicode.IsLetter(rune(c.in[c.at])) || unicode.IsDigit(rune(c.in[c.at]))) {
			c.at++
		}
		name := strings.ToLower(c.in[start:c.at])
		switch name {
		case "pi":
			return math.Pi, nil
		case "e":
			return math.E, nil
		}
		f, ok := functions[name]
		if !ok {
			return 0, fmt.Errorf("unknown name %q", name)
		}
		if !c.eat('(') {
			return 0, fmt.Errorf("%s needs parentheses", name)
		}
		var args []float64
		for !c.eat(')') {
			if len(args) > 0 && !c.eat(',') {
				return 0, fmt.Errorf("%s: missing )", name)
			}
			v, err := c.sum()
			if err != nil {
				return 0, err
			}
			args = append(args, v)
		}
		v, err := f(args...)
		if err != nil {
			return 0, fmt.Errorf("%s %w", name, err)
		}
		return v, nil
	}
	for c.at < len(c.in) && (c.in[c.at] >= '0' && c.in[c.at] <= '9' || c.in[c.at] == '.' || c.in[c.at] == '_') {
		c.at++
	}
	if c.at < len(c.in) && (c.in[c.at] == 'e' || c.in[c.at] == 'E') && c.at > start {
		end := c.at + 1
		if end < len(c.in) && (c.in[end] == '+' || c.in[end] == '-') {
			end++
		}
		if end < len(c.in) && c.in[end] >= '0' && c.in[end] <= '9' {
			for c.at = end; c.at < len(c.in) && c.in[c.at] >= '0' && c.in[c.at] <= '9'; c.at++ {
			}
		}
	}
	if c.at == start {
		if c.at >= len(c.in) {
			return 0, errors.New("the expression ends too soon")
		}
		return 0, fmt.Errorf("unexpected %q", c.in[c.at:])
	}
	return strconv.ParseFloat(strings.ReplaceAll(c.in[start:c.at], "_", ""), 64)
}

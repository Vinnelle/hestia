package metrics

import (
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
)

type Vec struct {
	Name  string
	Help  string
	Type  string
	Label string

	mu     sync.Mutex
	values map[string]float64
}

func NewCounter(name, help, label string) *Vec {
	return &Vec{Name: name, Help: help, Type: "counter", Label: label}
}

func NewGauge(name, help, label string) *Vec {
	return &Vec{Name: name, Help: help, Type: "gauge", Label: label}
}

func (v *Vec) Add(label string, d float64) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if v.values == nil {
		v.values = map[string]float64{}
	}
	v.values[label] += d
}

func (v *Vec) Set(label string, x float64) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if v.values == nil {
		v.values = map[string]float64{}
	}
	v.values[label] = x
}

func (v *Vec) Get(label string) float64 {
	v.mu.Lock()
	defer v.mu.Unlock()
	return v.values[label]
}

func escape(s string) string {
	return strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", `\n`).Replace(s)
}

func (v *Vec) write(b *strings.Builder) {
	v.mu.Lock()
	defer v.mu.Unlock()
	fmt.Fprintf(b, "# HELP %s %s\n# TYPE %s %s\n", v.Name, v.Help, v.Name, v.Type)
	keys := make([]string, 0, len(v.values))
	for k := range v.values {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		value := strconv.FormatFloat(v.values[k], 'g', -1, 64)
		if v.Label == "" {
			fmt.Fprintf(b, "%s %s\n", v.Name, value)
			continue
		}
		fmt.Fprintf(b, "%s{%s=\"%s\"} %s\n", v.Name, v.Label, escape(k), value)
	}
}

func Handler(vecs ...*Vec) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var b strings.Builder
		for _, v := range vecs {
			v.write(&b)
		}
		w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
		w.Write([]byte(b.String()))
	})
}

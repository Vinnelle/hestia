package prom

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestQueryParsesVectorsAndScalars(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("time") != "1700000000" {
			http.Error(w, "missing time", http.StatusBadRequest)
			return
		}
		switch r.URL.Query().Get("query") {
		case "up":
			w.Write([]byte(`{"status":"success","data":{"resultType":"vector","result":[{"metric":{"job":"a"},"value":[1700000000,"1"]},{"metric":{"job":"b"},"value":[1700000000,"0.5"]}]}}`))
		case "scalar(1)":
			w.Write([]byte(`{"status":"success","data":{"resultType":"scalar","result":[1700000000,"42"]}}`))
		default:
			w.WriteHeader(http.StatusBadRequest)
			w.Write([]byte(`{"status":"error","error":"bad query"}`))
		}
	}))
	defer srv.Close()
	c := &Client{BaseURL: srv.URL}
	at := time.Unix(1700000000, 0)

	samples, err := c.Query(context.Background(), "up", at)
	if err != nil || len(samples) != 2 || samples[1].Labels["job"] != "b" || samples[1].Value != 0.5 {
		t.Fatalf("vector = %+v, %v", samples, err)
	}
	v, ok, err := c.Scalar(context.Background(), "scalar(1)", at)
	if err != nil || !ok || v != 42 {
		t.Fatalf("scalar = %v %v %v", v, ok, err)
	}
	if _, err := c.Query(context.Background(), "nope", at); err == nil {
		t.Fatal("an error response was accepted")
	}
}

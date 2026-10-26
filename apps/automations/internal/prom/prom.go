package prom

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type Client struct {
	BaseURL string
	HTTP    *http.Client
}

type Sample struct {
	Labels map[string]string
	Value  float64
}

type response struct {
	Status string `json:"status"`
	Error  string `json:"error"`
	Data   struct {
		ResultType string          `json:"resultType"`
		Result     json.RawMessage `json:"result"`
	} `json:"data"`
}

func (c *Client) client() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	return &http.Client{Timeout: 30 * time.Second}
}

func value(pair []any) (float64, error) {
	if len(pair) != 2 {
		return 0, fmt.Errorf("malformed sample %v", pair)
	}
	s, ok := pair[1].(string)
	if !ok {
		return 0, fmt.Errorf("malformed sample value %v", pair[1])
	}
	return strconv.ParseFloat(s, 64)
}

func (c *Client) Query(ctx context.Context, query string, at time.Time) ([]Sample, error) {
	params := url.Values{"query": {query}}
	if !at.IsZero() {
		params.Set("time", strconv.FormatInt(at.Unix(), 10))
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimRight(c.BaseURL, "/")+"/api/v1/query?"+params.Encode(), nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.client().Do(req)
	if err != nil {
		return nil, fmt.Errorf("query %q: %w", query, err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, err
	}
	var out response
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, fmt.Errorf("query %q: %d %w", query, resp.StatusCode, err)
	}
	if out.Status != "success" {
		return nil, fmt.Errorf("query %q: %s", query, out.Error)
	}

	switch out.Data.ResultType {
	case "scalar":
		var pair []any
		if err := json.Unmarshal(out.Data.Result, &pair); err != nil {
			return nil, err
		}
		v, err := value(pair)
		if err != nil {
			return nil, err
		}
		return []Sample{{Labels: map[string]string{}, Value: v}}, nil
	case "vector":
		var rows []struct {
			Metric map[string]string `json:"metric"`
			Value  []any             `json:"value"`
		}
		if err := json.Unmarshal(out.Data.Result, &rows); err != nil {
			return nil, err
		}
		samples := make([]Sample, 0, len(rows))
		for _, row := range rows {
			v, err := value(row.Value)
			if err != nil {
				return nil, err
			}
			samples = append(samples, Sample{Labels: row.Metric, Value: v})
		}
		return samples, nil
	default:
		return nil, fmt.Errorf("query %q: unsupported result type %q", query, out.Data.ResultType)
	}
}

func (c *Client) Scalar(ctx context.Context, query string, at time.Time) (float64, bool, error) {
	samples, err := c.Query(ctx, query, at)
	if err != nil || len(samples) == 0 {
		return 0, false, err
	}
	return samples[0].Value, true, nil
}

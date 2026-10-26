package digest

import "time"

type Usage struct {
	Used  float64 `json:"used"`
	Peak  float64 `json:"peak"`
	Total float64 `json:"total"`
}

type Filesystem struct {
	Mount string  `json:"mount"`
	Used  float64 `json:"used_bytes"`
	Size  float64 `json:"size_bytes"`
}

type PodIssue struct {
	Namespace string `json:"namespace"`
	Pod       string `json:"pod"`
	Reason    string `json:"reason"`
}

type Restart struct {
	Namespace string `json:"namespace"`
	Pod       string `json:"pod"`
	Count     int    `json:"restarts"`
}

type NamespaceUsage struct {
	Namespace string  `json:"namespace"`
	Memory    float64 `json:"memory_bytes"`
	CPU       float64 `json:"cpu_cores"`
}

type Volume struct {
	Namespace string  `json:"namespace"`
	Claim     string  `json:"claim"`
	Used      float64 `json:"used_bytes"`
	Capacity  float64 `json:"capacity_bytes"`
}

type Cluster struct {
	Ready       bool             `json:"node_ready"`
	Talos       string           `json:"talos"`
	Kubernetes  string           `json:"kubernetes"`
	Kernel      string           `json:"kernel"`
	CPU         Usage            `json:"cpu_cores"`
	Memory      Usage            `json:"memory_bytes"`
	Filesystems []Filesystem     `json:"filesystems"`
	PodsRunning int              `json:"pods_running"`
	PodsTotal   int              `json:"pods_total"`
	PodIssues   []PodIssue       `json:"pod_issues"`
	Restarts    []Restart        `json:"restarts"`
	TopMemory   []NamespaceUsage `json:"top_memory"`
	FullVolumes []Volume         `json:"volumes_over_75_percent"`
	FailedJobs  []string         `json:"failed_jobs"`
}

type Host struct {
	Host     string  `json:"host"`
	Requests float64 `json:"requests"`
	Errors   float64 `json:"server_errors"`
	Bytes    float64 `json:"bytes_out"`
}

type Traffic struct {
	Requests         float64 `json:"requests"`
	PreviousRequests float64 `json:"previous_window_requests"`
	ServerErrors     float64 `json:"server_errors"`
	ClientErrors     float64 `json:"client_errors"`
	BytesOut         float64 `json:"bytes_out"`
	TunnelIn         float64 `json:"tunnel_bytes_in"`
	TunnelOut        float64 `json:"tunnel_bytes_out"`
	Hosts            []Host  `json:"hosts"`
}

type Alert struct {
	Name      string `json:"name"`
	Severity  string `json:"severity"`
	Namespace string `json:"namespace"`
	Firing    bool   `json:"firing_now"`
}

type Commit struct {
	SHA    string `json:"sha"`
	Title  string `json:"title"`
	Author string `json:"author"`
	URL    string `json:"-"`
}

type Merge struct {
	IID      int64  `json:"iid"`
	Title    string `json:"title"`
	Renovate bool   `json:"renovate"`
	URL      string `json:"-"`
}

type Pipeline struct {
	ID  int64  `json:"id"`
	Ref string `json:"ref"`
	URL string `json:"-"`
}

type ImageChange struct {
	Workload string `json:"workload"`
	From     string `json:"from"`
	To       string `json:"to"`
}

type Changes struct {
	Commits         []Commit          `json:"commits"`
	ImagePins       int               `json:"image_pin_commits"`
	Merged          []Merge           `json:"merged"`
	FailedPipelines []Pipeline        `json:"failed_pipelines"`
	OpenRenovate    int               `json:"open_renovate_merge_requests"`
	Images          []ImageChange     `json:"image_changes"`
	Added           []string          `json:"workloads_added"`
	Removed         []string          `json:"workloads_removed"`
	Upgrades        []string          `json:"upgrades"`
	Reviews         map[string]int    `json:"renovate_reviews"`
	Versions        map[string]string `json:"-"`
}

type ImageVulns struct {
	Image    string `json:"image"`
	Critical int    `json:"critical"`
}

type Security struct {
	Critical     int          `json:"critical"`
	High         int          `json:"high"`
	PrevCritical int          `json:"previous_critical"`
	PrevHigh     int          `json:"previous_high"`
	Known        bool         `json:"previous_known"`
	Worst        []ImageVulns `json:"worst_images"`
}

type Certificate struct {
	Name      string  `json:"name"`
	Namespace string  `json:"namespace"`
	Days      float64 `json:"days_left"`
	Ready     bool    `json:"ready"`
}

type AI struct {
	Model           string  `json:"model"`
	PromptTokens    float64 `json:"prompt_tokens"`
	GeneratedTokens float64 `json:"generated_tokens"`
	Speed           float64 `json:"generation_tokens_per_second"`
	GPU             string  `json:"gpu"`
	GPUTempMax      float64 `json:"gpu_temp_max_celsius"`
	GPUPowerAvg     float64 `json:"gpu_power_avg_watts"`
	VRAMUsed        float64 `json:"vram_used_bytes"`
	VRAMTotal       float64 `json:"vram_total_bytes"`
}

type Facts struct {
	From         time.Time     `json:"window_from"`
	To           time.Time     `json:"window_to"`
	First        bool          `json:"first_digest"`
	Cluster      Cluster       `json:"cluster"`
	Traffic      Traffic       `json:"traffic"`
	Alerts       []Alert       `json:"alerts"`
	Changes      Changes       `json:"changes"`
	Security     Security      `json:"security"`
	Certificates []Certificate `json:"certificates"`
	AI           AI            `json:"ai"`
	Gaps         []string      `json:"could_not_collect"`
}

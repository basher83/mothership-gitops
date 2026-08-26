#!/usr/bin/env bash
set -euo pipefail

readonly kubernetes_version="${KUBERNETES_VERSION:-1.36.0}"
readonly repository_root="$(git rev-parse --show-toplevel)"
readonly validation_tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/mothership-gitops-validate.XXXXXX")"

cleanup() {
  rm -rf -- "${validation_tmp_dir}"
}
trap cleanup EXIT

export HELM_CACHE_HOME="${validation_tmp_dir}/helm/cache"
export HELM_CONFIG_HOME="${validation_tmp_dir}/helm/config"
export HELM_DATA_HOME="${validation_tmp_dir}/helm/data"

mkdir -p "${validation_tmp_dir}/schema-cache"

cd "${repository_root}"

yaml_files=()
while IFS= read -r yaml_file; do
  yaml_files+=("${yaml_file}")
done < <(rg --files apps -g '*.yaml' | sort)

if [[ ${#yaml_files[@]} -eq 0 ]]; then
  echo "No application manifests found under apps/" >&2
  exit 1
fi

rendered_count=0
skipped_count=0

while IFS= read -r application_json; do
  source_file="$(printf '%s\n' "${application_json}" | yq -p=json -r '.file')"
  app_name="$(printf '%s\n' "${application_json}" | yq -p=json -r '.application.metadata.name')"
  release_name="$(printf '%s\n' "${application_json}" | yq -p=json -r '.application.spec.source.helm.releaseName // .application.metadata.name')"
  repo_url="$(printf '%s\n' "${application_json}" | yq -p=json -r '.application.spec.source.repoURL')"
  chart="$(printf '%s\n' "${application_json}" | yq -p=json -r '.application.spec.source.chart')"
  revision="$(printf '%s\n' "${application_json}" | yq -p=json -r '.application.spec.source.targetRevision')"
  namespace="$(printf '%s\n' "${application_json}" | yq -p=json -r '.application.spec.destination.namespace')"

  if [[ ! "${revision}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
    printf 'skip %-28s chart=%s revision=%s (not exact-pinned)\n' \
      "${app_name}" "${chart}" "${revision}"
    skipped_count=$((skipped_count + 1))
    continue
  fi

  value_files_count="$(printf '%s\n' "${application_json}" | yq -p=json -r '.application.spec.source.helm.valueFiles // [] | length')"
  parameters_count="$(printf '%s\n' "${application_json}" | yq -p=json -r '.application.spec.source.helm.parameters // [] | length')"
  if [[ "${value_files_count}" -ne 0 || "${parameters_count}" -ne 0 ]]; then
    echo "${source_file}: ${app_name} uses unsupported Helm valueFiles or parameters" >&2
    exit 1
  fi

  values_object_file="${validation_tmp_dir}/${app_name}-values-object.yaml"
  inline_values_file="${validation_tmp_dir}/${app_name}-inline-values.yaml"
  rendered_file="${validation_tmp_dir}/${app_name}-rendered.yaml"

  printf '%s\n' "${application_json}" \
    | yq -p=json -o=yaml '.application.spec.source.helm.valuesObject // {}' \
    > "${values_object_file}"

  inline_values="$(printf '%s\n' "${application_json}" | yq -p=json -r '.application.spec.source.helm.values // ""')"
  helm_args=(
    template "${release_name}"
    --version "${revision#v}"
    --namespace "${namespace}"
    --kube-version "${kubernetes_version}"
    --include-crds
    --skip-tests
    --values "${values_object_file}"
  )

  if [[ -n "${inline_values}" ]]; then
    printf '%s\n' "${inline_values}" > "${inline_values_file}"
    helm_args+=(--values "${inline_values_file}")
  fi

  if [[ "${repo_url}" == http://* || "${repo_url}" == https://* ]]; then
    helm_args+=(--repo "${repo_url}" "${chart}")
  else
    helm_args+=("oci://${repo_url#oci://}/${chart}")
  fi

  printf 'render %-26s chart=%s revision=%s\n' \
    "${app_name}" "${chart}" "${revision}"
  helm "${helm_args[@]}" > "${rendered_file}"

  kubeconform \
    -cache "${validation_tmp_dir}/schema-cache" \
    -ignore-missing-schemas \
    -kubernetes-version "${kubernetes_version}" \
    -strict \
    -summary \
    "${rendered_file}"

  rendered_count=$((rendered_count + 1))
done < <(
  yq eval-all -o=json -I=0 \
    'select(.kind == "Application" and .spec.source.chart != null) | {"file": filename, "application": .}' \
    "${yaml_files[@]}"
)

if [[ "${rendered_count}" -eq 0 ]]; then
  echo "No exact-pinned chart Applications were rendered" >&2
  exit 1
fi

printf 'Validated %d exact-pinned chart Application(s); skipped %d floating revision(s).\n' \
  "${rendered_count}" "${skipped_count}"

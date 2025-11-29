<!--
  マルチセレクトドロップダウンコンポーネント
  
  セレクト風の見た目でチェックボックス式の複数選択を提供
-->
<script lang="ts">
  import { onMount } from "svelte";

  interface Option {
    value: string;
    label: string;
    count?: number;
  }

  interface Props {
    value?: string[];
    options: Option[];
    placeholder?: string;
    label?: string;
    id?: string;
    onchange?: (selected: string[]) => void;
  }

  let {
    value = $bindable([]),
    options,
    placeholder = "すべて",
    label = "",
    id = "",
    onchange,
  }: Props = $props();

  let isOpen = $state(false);
  let dropdownElement: HTMLDivElement;

  // 選択されたアイテムの表示テキスト
  const displayText = $derived.by(() => {
    if (value.length === 0) {
      return placeholder;
    } else if (value.length === 1) {
      const option = options.find((opt) => opt.value === value[0]);
      return option ? option.label : value[0];
    } else {
      return `${value.length}件選択中`;
    }
  });

  // トグル処理
  function toggleDropdown() {
    isOpen = !isOpen;
  }

  // 選択状態をトグル
  function toggleOption(optionValue: string) {
    if (value.includes(optionValue)) {
      value = value.filter((v) => v !== optionValue);
    } else {
      value = [...value, optionValue];
    }

    // 変更を通知
    if (onchange) {
      onchange(value);
    }
  }

  // すべてクリア
  function clearAll() {
    value = [];
    if (onchange) {
      onchange(value);
    }
  }

  // 外部クリックで閉じる
  function handleClickOutside(event: MouseEvent) {
    if (dropdownElement && !dropdownElement.contains(event.target as Node)) {
      isOpen = false;
    }
  }

  onMount(() => {
    document.addEventListener("click", handleClickOutside);
    return () => {
      document.removeEventListener("click", handleClickOutside);
    };
  });
</script>

<div class="relative" bind:this={dropdownElement}>
  {#if label}
    <label
      for={id}
      class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1"
    >
      {label}
    </label>
  {/if}

  <!-- ドロップダウンボタン -->
  <button
    type="button"
    {id}
    onclick={toggleDropdown}
    class="w-full h-10 px-3 py-2 border border-gray-300 dark:border-gray-600 rounded bg-white dark:bg-gray-700 text-gray-900 dark:text-white text-left flex items-center justify-between hover:border-gray-400 dark:hover:border-gray-500 transition-colors"
    class:ring-2={isOpen}
    class:ring-blue-500={isOpen}
  >
    <span
      class="truncate flex-1 min-w-0"
      class:text-gray-500={value.length === 0}
    >
      {displayText}
    </span>
    <div class="flex items-center gap-1 shrink-0">
      {#if value.length > 0}
        <span
          role="button"
          tabindex="0"
          onclick={(e) => {
            e.stopPropagation();
            clearAll();
          }}
          onkeydown={(e) => {
            if (e.key === "Enter" || e.key === " ") {
              e.stopPropagation();
              e.preventDefault();
              clearAll();
            }
          }}
          class="p-1 hover:bg-gray-200 dark:hover:bg-gray-600 rounded transition-colors cursor-pointer"
          title="クリア"
        >
          <i class="fas fa-times text-xs"></i>
        </span>
      {/if}
      <i class="fas fa-chevron-{isOpen ? 'up' : 'down'} text-sm"></i>
    </div>
  </button>

  <!-- ドロップダウンメニュー -->
  {#if isOpen}
    <div
      class="absolute z-50 w-full mt-1 bg-white dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded shadow-lg max-h-60 overflow-y-auto"
    >
      {#if options.length === 0}
        <div class="px-3 py-2 text-sm text-gray-500 dark:text-gray-400">
          選択肢がありません
        </div>
      {:else}
        {#each options as option}
          <label
            class="flex items-center px-3 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 cursor-pointer transition-colors"
          >
            <input
              type="checkbox"
              checked={value.includes(option.value)}
              onchange={() => toggleOption(option.value)}
              class="mr-2 rounded border-gray-300 dark:border-gray-600 text-blue-600 focus:ring-blue-500"
            />
            <span class="flex-1 text-sm text-gray-900 dark:text-gray-100">
              {option.label}
              {#if option.count !== undefined}
                <span class="text-gray-500 dark:text-gray-400"
                  >({option.count})</span
                >
              {/if}
            </span>
          </label>
        {/each}
      {/if}
    </div>
  {/if}
</div>

<style>
  /* スクロールバーのスタイリング（オプション） */
  .overflow-y-auto::-webkit-scrollbar {
    width: 8px;
  }

  .overflow-y-auto::-webkit-scrollbar-track {
    background: transparent;
  }

  .overflow-y-auto::-webkit-scrollbar-thumb {
    background: #cbd5e0;
    border-radius: 4px;
  }

  :global(.dark) .overflow-y-auto::-webkit-scrollbar-thumb {
    background: #4b5563;
  }

  .overflow-y-auto::-webkit-scrollbar-thumb:hover {
    background: #a0aec0;
  }

  :global(.dark) .overflow-y-auto::-webkit-scrollbar-thumb:hover {
    background: #6b7280;
  }
</style>

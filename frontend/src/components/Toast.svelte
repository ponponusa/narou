<!--
  トースト通知コンポーネント
  
  エラーや成功メッセージを画面右上に表示
-->
<script lang="ts">
  interface ToastMessage {
    id: number;
    type: 'success' | 'error' | 'info' | 'warning';
    message: string;
    duration?: number;
  }

  let toasts = $state<ToastMessage[]>([]);
  let nextId = 0;

  /**
   * トースト通知を表示
   */
  export function show(
    message: string,
    type: 'success' | 'error' | 'info' | 'warning' = 'info',
    duration: number = 5000
  ) {
    const id = nextId++;
    const toast: ToastMessage = { id, type, message, duration };
    
    toasts = [...toasts, toast];
    
    if (duration > 0) {
      setTimeout(() => {
        remove(id);
      }, duration);
    }
  }

  /**
   * トースト通知を削除
   */
  function remove(id: number) {
    toasts = toasts.filter(t => t.id !== id);
  }

  /**
   * タイプに応じたスタイルクラスを取得
   */
  function getTypeClass(type: ToastMessage['type']): string {
    const classes = {
      success: 'bg-green-500 text-white',
      error: 'bg-red-500 text-white',
      warning: 'bg-yellow-500 text-white',
      info: 'bg-blue-500 text-white',
    };
    return classes[type];
  }

  /**
   * タイプに応じたアイコンを取得
   */
  function getIcon(type: ToastMessage['type']): string {
    const icons = {
      success: '✓',
      error: '✕',
      warning: '⚠',
      info: 'ℹ',
    };
    return icons[type];
  }
</script>

<!-- トースト通知コンテナ -->
<div class="fixed top-4 right-4 z-50 flex flex-col gap-2 pointer-events-none">
  {#each toasts as toast (toast.id)}
    <div
      class="pointer-events-auto flex items-center gap-3 px-4 py-3 rounded-lg shadow-lg {getTypeClass(toast.type)} min-w-[300px] max-w-md animate-slide-in"
      role="alert"
    >
      <span class="text-xl font-bold">{getIcon(toast.type)}</span>
      <p class="flex-1 text-sm">{toast.message}</p>
      <button
        onclick={() => remove(toast.id)}
        class="text-white hover:text-gray-200 transition-colors"
        aria-label="閉じる"
      >
        ✕
      </button>
    </div>
  {/each}
</div>

<style>
  @keyframes slide-in {
    from {
      transform: translateX(100%);
      opacity: 0;
    }
    to {
      transform: translateX(0);
      opacity: 1;
    }
  }

  .animate-slide-in {
    animation: slide-in 0.3s ease-out;
  }
</style>

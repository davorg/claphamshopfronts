(() => {
  const dialog = document.querySelector('.photo-modal');
  if (!dialog || typeof dialog.showModal !== 'function') return;

  let opener;
  document.querySelectorAll('[data-photo-modal]').forEach(link => {
    link.addEventListener('click', event => {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      opener = link;
      const image = dialog.querySelector('img');
      image.src = link.href;
      image.alt = link.dataset.photoAlt;
      image.width = Number(link.dataset.photoWidth);
      image.height = Number(link.dataset.photoHeight);
      dialog.setAttribute('aria-label', 'Larger photograph of ' + link.dataset.photoName);
      dialog.showModal();
      document.body.classList.add('photo-modal-open');
    });
  });

  dialog.addEventListener('click', event => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) {
      dialog.close();
    }
  });

  dialog.addEventListener('close', () => {
    document.body.classList.remove('photo-modal-open');
    if (opener?.isConnected) opener.focus({preventScroll: true});
  });
})();
